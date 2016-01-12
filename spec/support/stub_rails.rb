class Rails
  def self.root
    @root ||= Pathname.new(File.expand_path('../../', __FILE__)).freeze
  end

  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
end
