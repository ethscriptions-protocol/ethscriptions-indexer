module ImporterSingleton
  def self.instance=(importer)
    @instance = importer
  end
  
  def self.instance
    @instance ||= EthBlockImporter.new
  end
end
