class BlockValidator
  attr_reader :errors, :stats

  # Exception for transient errors that should trigger retries
  # This is informational - all exceptions are treated as transient
  class TransientValidationError < StandardError; end

  def initialize
    # Initialize validation state
    reset_validation_state
  end

  def validate_l1_block(l1_block_number, l2_block_hashes)
    reset_validation_state
    validation_start_time = Time.current

    Rails.logger.debug "Validating L1 block #{l1_block_number} with #{l2_block_hashes.size} L2 blocks"

    # Fetch expected data from API
    expected = fetch_expected_data(l1_block_number)

    # Get actual data from L2 events
    actual_events = aggregate_l2_events(l2_block_hashes)

    # Historical block tag for reads as-of this L1 block's L2 application
    # Use EIP-1898 with blockHash for reorg-safety
    historical_block_tag = l2_block_hashes.any? ? { blockHash: l2_block_hashes.last } : 'latest'

    # Compare events
    compare_events(expected, actual_events, l1_block_number)

    # Verify storage state
    verify_storage_state(expected, l1_block_number, historical_block_tag)

    # Build comprehensive result with full debugging data
    success = @errors.empty?
    validation_duration = Time.current - validation_start_time

    # Return comprehensive debugging information
    result = OpenStruct.new(
      success: success,
      errors: @errors,
      l1_block: l1_block_number,
      stats: {
        # Basic validation stats
        expected_creations: Array(expected[:creations]).size,
        actual_creations: Array(actual_events[:creations]).size,
        expected_transfers: Array(expected[:transfers]).size,
        actual_transfers: Array(actual_events[:transfers]).size,
        storage_checks: @storage_checks_performed.value,
        errors_count: @errors.size,

        # L1 to L2 block mapping
        l1_to_l2_mapping: {
          l1_block: l1_block_number,
          l2_blocks: l2_block_hashes.map.with_index { |hash, i|
            {
              index: i,
              hash: hash,
              block_tag: i == l2_block_hashes.size - 1 ? historical_block_tag : { blockHash: hash }
            }
          }
        },

        # Complete raw data for debugging (sanitized for JSON storage)
        raw_expected_data: {
          creations: sanitize_for_json(expected[:creations] || []),
          transfers: sanitize_for_json(expected[:transfers] || []),
        },

        raw_actual_data: {
          creations: sanitize_for_json(actual_events[:creations] || []),
          transfers: sanitize_for_json(actual_events[:transfers] || []),
          l2_events_source: "geth_block_receipts"
        },

        # Actual comparisons performed during validation (not recreated)
        actual_comparisons: @debug_data,

        # Performance and metadata
        validation_timing: {
          duration_ms: (validation_duration * 1000).round(2),
          started_at: validation_start_time.iso8601,
          completed_at: Time.current.iso8601
        }
      }
    )

    result
  end

  private

  def reset_validation_state
    @errors = Concurrent::Array.new
    @storage_checks_performed = Concurrent::AtomicFixnum.new(0)

    # Reset debugging instrumentation
    @debug_data = {
      creation_comparisons: [],
      transfer_comparisons: [],
      storage_checks: [],
      event_comparisons: []
    }
  end

  def load_genesis_transaction_hashes
    # Load genesis ethscriptions from the JSON file
    genesis_file = Rails.root.join('contracts', 'script', 'genesisEthscriptions.json')
    genesis_data = JSON.parse(File.read(genesis_file))

    # Extract all ethscription IDs (L1 tx hashes) from the ethscriptions array
    genesis_data['ethscriptions'].map { |e| e['transaction_hash'] }
  end

  def fetch_expected_data(l1_block_number)
    EthscriptionsApiClient.fetch_block_data(l1_block_number)
  rescue => e
    # Treat any API client failure as transient to avoid false negatives
    Rails.logger.warn "Transient API error for block #{l1_block_number}: #{e.class}: #{e.message}"
    raise TransientValidationError, e.message
  end

  def aggregate_l2_events(block_hashes)
    ImportProfiler.start("aggregate_l2_events")
    all_creations = []
    all_transfers = []

    block_hashes.each do |block_hash|
      begin
        receipts = EthRpcClient.l2.call('eth_getBlockReceipts', [block_hash])
        if receipts.nil?
          # Treat missing receipts as transient infrastructure issue
          error_msg = "No receipts returned for L2 block #{block_hash}"
          Rails.logger.warn "Transient L2 error: #{error_msg}"
          raise TransientValidationError, error_msg
        end

        data = EventDecoder.decode_block_receipts(receipts)
        all_creations.concat(data[:creations])
        all_transfers.concat(data[:transfers])  # Ethscriptions protocol transfers
      rescue => e
        # Treat any L2 RPC failure as transient to avoid false negatives
        error_msg = "Failed to get receipts for block #{block_hash}: #{e.message}"
        Rails.logger.warn "Transient L2 error: #{error_msg}"
        raise TransientValidationError, error_msg
      end
    end

    result = {
      creations: all_creations,
      transfers: all_transfers
    }
    ImportProfiler.stop("aggregate_l2_events")
    result
  end

  def compare_events(expected, actual, l1_block_num)
    expected_creations = Array(expected[:creations])
    expected_transfers = Array(expected[:transfers])

    # Calculate the L1 block where L2 block 1 happened (genesis + 1)
    l2_block_1_l1_block = Integer(ENV.fetch("L1_GENESIS_BLOCK")) + 1

    # Special handling for the L1 block where L2 block 1 happened - genesis events are emitted then
    if l1_block_num == l2_block_1_l1_block
      genesis_hashes = load_genesis_transaction_hashes
      Rails.logger.info "L1 Block #{l1_block_num} (L2 block 1): Expecting #{genesis_hashes.size} genesis events in addition to regular events"

      # Add genesis hashes to expected creations for this block
      expected_creation_hashes = (expected_creations.map { |c| c[:tx_hash].downcase } + genesis_hashes.map(&:downcase)).to_set

      # Also expect transfers for genesis ethscriptions
      # These will be EthscriptionTransferred events from creator to initial owner
      # We'll validate them separately since we don't have full transfer data
    else
      expected_creation_hashes = expected_creations.map { |c| c[:tx_hash].downcase }.to_set
    end

    actual_creation_hashes = actual[:creations].map { |c| c[:tx_hash].downcase }.to_set

    # Find missing creations
    missing = expected_creation_hashes - actual_creation_hashes
    missing.each do |tx_hash|
      @errors << "Missing creation event: #{tx_hash} in L1 block #{l1_block_num}"
    end

    # Find unexpected creations (but don't warn about genesis events in the L1 block for L2 block 1)
    unexpected = actual_creation_hashes - expected_creation_hashes
    if l1_block_num != l2_block_1_l1_block
      # binding.irb if unexpected.present?
      unexpected.each do |tx_hash|
        @errors << "Unexpected creation event: #{tx_hash} in L1 block #{l1_block_num}"
      end
    end

    # Compare creation details for matching transactions
    expected_creations.each do |exp_creation|
      act_creation = actual[:creations].find { |a|
        a[:tx_hash]&.downcase == exp_creation[:tx_hash]&.downcase
      }

      next unless act_creation

      if !addresses_match?(exp_creation[:creator], act_creation[:creator])
        @errors << "Creator mismatch for #{exp_creation[:tx_hash]}: expected #{exp_creation[:creator]}, got #{act_creation[:creator]}"
      end

      if !addresses_match?(exp_creation[:initial_owner], act_creation[:initial_owner])
        @errors << "Initial owner mismatch for #{exp_creation[:tx_hash]}: expected #{exp_creation[:initial_owner]}, got #{act_creation[:initial_owner]}"
      end
    end

    # Use protocol transfers for validation (they match Ethscriptions semantics)
    # These have the correct 'from' address (creator/owner, not address(0))
    compare_transfers(expected_transfers, actual[:transfers], l1_block_num)
  end

  def compare_transfers(expected, actual, l1_block_num)
    # Calculate the L1 block where L2 block 1 happened
    l2_block_1_l1_block = Integer(ENV.fetch("L1_GENESIS_BLOCK")) + 1

    # Group transfers by token_id for easier comparison
    expected_by_token = expected.group_by { |t| t[:token_id]&.downcase }
    actual_by_token = actual.group_by { |t| t[:token_id]&.downcase }

    # Check for missing transfers
    (expected_by_token.keys - actual_by_token.keys).each do |token_id|
      @errors << "Missing transfer events for token #{token_id} in L1 block #{l1_block_num}"
    end

    # Check for unexpected transfers (but be lenient for the L1 block where L2 block 1 happened due to genesis events)
    if l1_block_num == l2_block_1_l1_block
      # For the L1 block where L2 block 1 happened, we expect genesis transfer events that won't be in the API data
      # Just log them as info instead of treating them as errors
      (actual_by_token.keys - expected_by_token.keys).each do |token_id|
        Rails.logger.info "Genesis transfer event for token #{token_id} (expected for L2 block 1)"
      end
    else
      (actual_by_token.keys - expected_by_token.keys).each do |token_id|
        @errors << "Unexpected transfer events for token #{token_id}"
      end
    end

    # Compare transfer details
    expected_by_token.each do |token_id, exp_transfers|
      act_transfers = actual_by_token[token_id] || []

      expected_counts = build_transfer_counts(exp_transfers)
      actual_counts = build_transfer_counts(act_transfers)

      expected_counts.each do |signature, expected_count|
        actual_count = actual_counts[signature] || 0
        next if actual_count >= expected_count

        missing_count = expected_count - actual_count
        example = find_transfer_by_signature(exp_transfers, signature)
        @errors << "Missing transfer event(x#{missing_count}) for token #{token_id}: #{transfer_debug_string(example)}"
      end

      actual_counts.each do |signature, actual_count|
        expected_count = expected_counts[signature] || 0
        next if actual_count <= expected_count

        extra = actual_count - expected_count
        example = find_transfer_by_signature(act_transfers, signature)
        message = "Unexpected transfer event(x#{extra}) for token #{token_id}: #{transfer_debug_string(example)}"
        if l1_block_num == l2_block_1_l1_block
          Rails.logger.info "#{message} (allowed for L2 block 1 genesis events)"
        else
          @errors << message
        end
      end
    end
  end

  def build_transfer_counts(transfers)
    counts = Hash.new(0)
    transfers.each do |transfer|
      counts[transfer_signature_basic(transfer)] += 1
    end
    counts
  end

  def transfer_signature_basic(transfer)
    [
      transfer[:token_id]&.downcase,
      transfer[:from]&.downcase,
      transfer[:to]&.downcase
    ]
  end

  def find_transfer_by_signature(transfers, signature)
    transfers.find { |transfer| transfer_signature_basic(transfer) == signature }
  end

  def transfer_debug_string(transfer)
    return 'no metadata' unless transfer

    parts = [
      ("from=#{transfer[:from]}" if transfer[:from]),
      ("to=#{transfer[:to]}" if transfer[:to]),
      ("tx=#{transfer[:tx_hash]}" if transfer[:tx_hash]),
      ("tx_index=#{transfer[:transaction_index]}" if transfer[:transaction_index]),
      ("log_index=#{transfer[:log_index] || transfer[:event_log_index]}" if transfer[:log_index] || transfer[:event_log_index])
    ].compact

    return 'no metadata' if parts.empty?

    parts.join(', ')
  end

  def binary_equal?(val1, val2)
    return true if val1.nil? && val2.nil?
    return false if val1.nil? || val2.nil?
    val1.to_s.b == val2.to_s.b
  end

  def verify_storage_state(expected_data, l1_block_num, block_tag)
    ImportProfiler.start("storage_verification")

    # Sequentially verify each creation on the main thread
    Array(expected_data[:creations]).each do |creation|
      verify_ethscription_storage(creation, l1_block_num, block_tag)
    end

    # Verify ownership after transfers
    verify_transfer_ownership(Array(expected_data[:transfers]), block_tag)

    ImportProfiler.stop("storage_verification")
  end

  def verify_ethscription_storage(creation, l1_block_num, block_tag)
    tx_hash = creation[:tx_hash]

    # Use get_ethscription_with_content to fetch both metadata and content
    begin
      stored = StorageReader.get_ethscription_with_content(tx_hash, block_tag: block_tag)
    rescue => e
      # RPC/network error - treat as transient inability to validate
      Rails.logger.warn "Transient storage error for #{tx_hash}: #{e.message}"
      raise TransientValidationError, "Storage read failed for #{tx_hash}: #{e.message}"
    end

    @storage_checks_performed.increment

    if stored.nil?
      # Ethscription genuinely doesn't exist in contract - this is a validation failure
      @errors << "Ethscription #{tx_hash} not found in contract storage"
      return
    end

    # Verify creator (with instrumentation)
    creator_match = addresses_match?(stored[:creator], creation[:creator])
    creator_check = record_comparison(
      "storage_creator_check",
      tx_hash,
      creation[:creator],
      stored[:creator],
      creator_match,
      { l1_block: l1_block_num }
    )

    if !creator_match
      @errors << "Storage creator mismatch for #{tx_hash}: stored=#{stored[:creator]}, expected=#{creation[:creator]}"
    end

    # Verify initial owner (with instrumentation)
    initial_owner_match = addresses_match?(stored[:initial_owner], creation[:initial_owner])
    initial_owner_check = record_comparison(
      "storage_initial_owner_check",
      tx_hash,
      creation[:initial_owner],
      stored[:initial_owner],
      initial_owner_match,
      { l1_block: l1_block_num }
    )

    if !initial_owner_match
      @errors << "Storage initial_owner mismatch for #{tx_hash}: stored=#{stored[:initial_owner]}, expected=#{creation[:initial_owner]}"
    end

    # Verify L1 block number (with instrumentation)
    l1_block_match = stored[:l1_block_number] == l1_block_num
    l1_block_check = record_comparison(
      "storage_l1_block_check",
      tx_hash,
      l1_block_num,
      stored[:l1_block_number],
      l1_block_match,
      { l1_block: l1_block_num }
    )

    if !l1_block_match
      @errors << "Storage L1 block mismatch for #{tx_hash}: stored=#{stored[:l1_block_number]}, expected=#{l1_block_num}"
    end

    # Verify content - API client already decoded b64_content to content field (with instrumentation)
    if creation[:content]
      content_match = stored[:content] == creation[:content]

      # Store first 50 chars for debugging (full comparison still done)
      # Handle binary content by encoding as base64 for JSON serialization
      expected_preview = safe_content_preview(creation[:content])
      actual_preview = safe_content_preview(stored[:content])

      content_check = record_comparison(
        "storage_content_check",
        tx_hash,
        expected_preview,
        actual_preview,
        content_match,
        {
          l1_block: l1_block_num,
          expected_length: creation[:content]&.length,
          actual_length: stored[:content]&.length,
          b64_content_preview: creation[:b64_content]&.[](0..100)
        }
      )

      if !content_match
        @errors << "Storage content mismatch for #{tx_hash}: stored length=#{stored[:content]&.length}, expected length=#{creation[:content]&.length}"
      end
    end

    # Verify content_uri_sha - this is the hash of the original content URI
    stored_uri_hash = stored[:content_uri_sha]&.downcase&.delete_prefix('0x')
    if creation[:content_uri]
      # Hash the content_uri from the API to compare
      expected_uri_hash = Digest::SHA256.hexdigest(creation[:content_uri]).downcase
      if stored_uri_hash != expected_uri_hash
        @errors << "Storage content_uri_sha mismatch for #{tx_hash}: stored=#{stored_uri_hash}, expected=#{expected_uri_hash}"
      end
    end

    # Verify content_hash - always present in API, must match exactly (with instrumentation)
    stored_sha = stored[:content_hash]&.downcase&.delete_prefix('0x')
    expected_sha = creation[:content_hash].downcase.delete_prefix('0x')
    content_hash_match = stored_sha == expected_sha
    content_hash_check = record_comparison(
      "storage_content_hash_check",
      tx_hash,
      expected_sha,
      stored_sha,
      content_hash_match,
      { l1_block: l1_block_num }
    )

    if !content_hash_match
      @errors << "Storage content_hash mismatch for #{tx_hash}: stored=#{stored[:content_hash]}, expected=#{creation[:content_hash]}"
    end

    # Verify mimetype - normalize to binary for comparison (with instrumentation)
    mimetype_match = binary_equal?(stored[:mimetype], creation[:mimetype])
    mimetype_check = record_comparison(
      "storage_mimetype_check",
      tx_hash,
      creation[:mimetype],
      stored[:mimetype],
      mimetype_match,
      { l1_block: l1_block_num }
    )

    if !mimetype_match
      @errors << "Storage mimetype mismatch for #{tx_hash}: stored=#{stored[:mimetype]}, expected=#{creation[:mimetype]}"
    end

    # Note: media_type and mime_subtype are no longer stored in the contract
    # They are derived from mimetype in StorageReader for backward compatibility

    # Verify esip6 flag - must match exactly (with instrumentation)
    esip6_match = stored[:esip6] == creation[:esip6]
    record_comparison("storage_esip6_check", tx_hash, creation[:esip6], stored[:esip6], esip6_match, { l1_block: l1_block_num })
    if !esip6_match
      @errors << "Storage esip6 mismatch for #{tx_hash}: stored=#{stored[:esip6]}, expected=#{creation[:esip6]}"
    end
  end

  def verify_transfer_ownership(transfers, block_tag)
    # Replay transfers in deterministic order to determine the true final owner
    final_owners = {}

    sorted_transfers = Array(transfers).each_with_index.sort_by do |transfer, original_index|
      block_number = transfer[:block_number]
      transaction_index = transfer[:transaction_index]

      if block_number.nil? || transaction_index.nil?
        raise "Transfer missing ordering metadata: #{transfer.inspect}"
      end

      log_index = transfer[:event_log_index] || transfer[:log_index]

      [
        block_number.to_i,
        transaction_index.to_i,
        log_index.nil? ? -1 : log_index.to_i, # calldata transfers (no log) happen before events
        original_index
      ]
    end.map { |transfer, _| transfer }

    sorted_transfers.each do |transfer|
      token_id = transfer[:token_id]
      to_address = transfer[:to]
  
      if token_id.blank? || to_address.blank?
        raise "Transfer missing token_id or recipient: #{transfer.inspect}"
      end
  
      final_owners[token_id.downcase] = to_address.downcase
    end

    # Verify each token's final owner
    final_owners.each do |token_id, expected_owner|
      # First check if the ethscription exists in storage
      begin
        ethscription = StorageReader.get_ethscription(token_id, block_tag: block_tag)
      rescue => e
        # RPC/network error - treat as transient inability to validate
        Rails.logger.warn "Transient storage error for #{token_id}: #{e.message}"
        raise TransientValidationError, "Storage read failed for #{token_id}: #{e.message}"
      end

      if ethscription.nil?
        # Token genuinely doesn't exist - this is a validation failure
        @errors << "Token #{token_id} not found in storage"
        next
      end

      begin
        actual_owner = StorageReader.get_owner(token_id, block_tag: block_tag)
      rescue => e
        # RPC/network error - treat as transient inability to validate
        Rails.logger.warn "Transient owner read error for #{token_id}: #{e.message}"
        raise TransientValidationError, "Owner read failed for #{token_id}: #{e.message}"
      end

      @storage_checks_performed.increment

      if actual_owner.nil?
        # Owner doesn't exist (shouldn't happen if ethscription exists) - validation failure
        @errors << "Could not verify owner of token #{token_id}"
        next
      end

      unless addresses_match?(actual_owner, expected_owner)
        @errors << "Ownership mismatch for token #{token_id}: stored=#{actual_owner}, expected=#{expected_owner}"
      end
    end
  end

  def addresses_match?(addr1, addr2)
    return false if addr1.nil? || addr2.nil?
    addr1.downcase == addr2.downcase
  end

  # Instrumentation helper to record comparison results
  def record_comparison(type, identifier, expected, actual, match_result, extra_data = {})
    comparison = {
      type: type,
      identifier: identifier,
      expected: expected,
      actual: actual,
      match: match_result,
      timestamp: Time.current.iso8601
    }.merge(extra_data)

    case type
    when /creation/
      @debug_data[:creation_comparisons] << comparison
    when /transfer/
      @debug_data[:transfer_comparisons] << comparison
    when /storage/
      @debug_data[:storage_checks] << comparison
    else
      @debug_data[:event_comparisons] << comparison
    end

    comparison
  end

  # Safely create content preview for JSON serialization
  def safe_content_preview(content, length: 50)
    return "" if content.nil?

    # Use inspect to safely handle any encoding/binary data
    preview = content[0..length].inspect
    preview + (content.length > length ? "..." : "")
  end


  # Sanitize data structures for JSON serialization
  def sanitize_for_json(data)
    case data
    when Array
      data.map { |item| sanitize_for_json(item) }
    when Hash
      data.transform_values { |value| sanitize_for_json(value) }
    when String
      # Only use inspect if string is not safe UTF-8
      if data.valid_encoding? && (data.encoding == Encoding::UTF_8 || data.ascii_only?)
        data  # Safe to store as-is
      else
        data.inspect  # Binary or invalid encoding - use inspect for safety
      end
    else
      data
    end
  end
end
