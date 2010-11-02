module ScrapedDocument
  require 'open-uri'
  
  def self.included(base)
    base.class_eval do
      has_attached_file :document, :path => ':rails_root/public/system/:class/:id/:style/:filename', :url => '/system/:class/:id/:style/:filename'
      scope :without_local_copy, where("url is not null and url != '' and document_file_name is null")

      before_update :queue_document_download, :if => :refresh_document?
      after_create :queue_document_download

      # cancel post-processing now, and set flag...
      before_document_post_process do |obj|
        if obj.refresh_document?
          false # halts processing
        end
      end

    end
  end

  def sync_document!
    self.document = do_download_file
    self.document.reprocess!
    self.save(false)
  end

  def refresh_document?
    self.url_changed? || (!self.url.blank? && !self.document?)
  end

  private

  def queue_document_download
    Delayed::Job.enqueue(ScrapedDocumentJob.new(self.class, self.id)) if self.url?
  end

  def do_download_file
    Timeout::timeout(10) do
      io = open(URI.parse(url))
      def io.original_filename; base_uri.path.split('/').last; end
      io.original_filename.blank? ? nil : io
    end
  rescue OpenURI::HTTPError => e
    puts "OpenURL error: #{e}"
    # catch url errors with validations instead of exceptions (Errno::ENOENT, OpenURI::HTTPError, etc...)
  rescue SystemCallError => e
    # eg. connection reset by peer
    puts "System call error: #{e}"
    raise
  end

end