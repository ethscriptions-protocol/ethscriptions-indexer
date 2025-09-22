class Ethscription < ApplicationRecord
  include FacetRailsCommon::OrderQuery
    
  initialize_order_query({
    newest_first: [[:block_number, :desc], [:transaction_index, :desc, unique: true]],
    oldest_first: [[:block_number, :asc], [:transaction_index, :asc, unique: true]]
  }, page_key_attributes: [:transaction_hash])
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true,
    inverse_of: :ethscriptions
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true, inverse_of: :ethscription
  
  has_many :ethscription_transfers, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_many :ethscription_ownership_versions, foreign_key: :ethscription_transaction_hash, primary_key: :transaction_hash, inverse_of: :ethscription
  
  has_one :token_item,
    foreign_key: :ethscription_transaction_hash,
    primary_key: :transaction_hash,
    inverse_of: :ethscription
  
  has_one :token,
    foreign_key: :deploy_ethscription_transaction_hash,
    primary_key: :transaction_hash,
    inverse_of: :deploy_ethscription
    
  has_one :attachment,
    class_name: 'EthscriptionAttachment',
    foreign_key: :sha,
    primary_key: :attachment_sha,
    inverse_of: :ethscriptions
    
  scope :with_token_tick_and_protocol, -> (token_tick, token_protocol) {
    joins(token_item: :token)
    .where(tokens: {tick: token_tick, protocol: token_protocol})
    .order('token_items.block_number DESC, token_items.transaction_index DESC')
  }
  
  before_validation :set_derived_attributes, on: :create
  after_create :create_initial_transfer!
  
  MAX_MIMETYPE_LENGTH = 1000
  
  def latest_transfer
    ethscription_transfers.sort_by do |transfer|
      [transfer.block_number, transfer.transaction_index, transfer.transfer_index]
    end.last
  end
  
  def create_initial_transfer!
    ethscription_transfers.create!(
      {
        from_address: creator,
        to_address: initial_owner,
        transfer_index: eth_transaction.transfer_index,
      }.merge(eth_transaction.transfer_attrs)
    )
  end
  
  def current_ownership_version
    ethscription_ownership_versions.newest_first.first
  end
  
  def content
    parsed_data_uri&.decoded_data
  end
  
  def valid_data_uri?
    DataUri.valid?(content_uri)
  end
  
  def parsed_data_uri
    return unless valid_data_uri?
    DataUri.new(content_uri)
  end
  
  def content_sha
    "0x" + Digest::SHA256.hexdigest(content_uri)
  end

  def esip6
    DataUri.esip6?(content_uri)
  end
  
  def mimetype
    parsed_data_uri&.mimetype&.first(MAX_MIMETYPE_LENGTH)
  end

  def media_type
    mimetype&.split('/')&.first
  end

  def mime_subtype
    mimetype&.split('/')&.last
  end
  
  def valid_ethscription?
    initial_owner.present? &&
    valid_data_uri? &&
    (esip6 || content_is_unique?)
  end
  
  def content_is_unique?
    !Ethscription.exists?(content_sha: content_sha)
  end
  
  def self.scope_checksum(scope)
    subquery = scope.select(:transaction_hash)
    hash_value = Ethscription.from(subquery, :ethscriptions)
      .select("encode(digest(array_to_string(array_agg(transaction_hash), ''), 'sha256'), 'hex')
        as hash_value")
      .take
      .hash_value
  end
  
  def as_json(options = {})
    super(options.merge(
        except: [
          :id,
          :created_at,
          :updated_at
        ]
      )
    ).tap do |json|
      if options[:include_transfers]
        json[:ethscription_transfers] = ethscription_transfers.as_json
      end
      if options[:include_latest_transfer]
        json[:latest_transfer] = latest_transfer.as_json
      end

      if json['attachment_sha']
        json['attachment_path'] = Rails.application.routes.url_helpers.attachment_ethscription_path(id: transaction_hash)
      end

      json['b64_content'] = Base64.strict_encode64(content)
    end
  end
  
  private
  
  def set_derived_attributes
    self[:content_sha] = content_sha
    self[:esip6] = esip6
    self[:mimetype] = mimetype
    self[:media_type] = media_type
    self[:mime_subtype] = mime_subtype
  end
end
