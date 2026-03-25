Pod::Spec.new do |s|
  s.name             = 'FeedReaderCore'
  s.version          = '1.2.0'
  s.summary          = 'RSS/Atom feed parsing and management library for iOS.'
  s.description      = <<-DESC
    FeedReaderCore provides models, RSS/Atom parsing, OPML import/export,
    feed health monitoring, keyword extraction, and article archiving.
    A lightweight, dependency-free Swift library for building feed readers.
  DESC
  s.homepage         = 'https://github.com/sauravbhattacharya001/FeedReader'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Saurav Bhattacharya' => 'online.saurav@gmail.com' }
  s.source           = { :git => 'https://github.com/sauravbhattacharya001/FeedReader.git', :tag => "v#{s.version}" }
  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/FeedReaderCore/**/*.swift'
  s.frameworks       = 'Foundation'
end
