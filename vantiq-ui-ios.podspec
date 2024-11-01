#
# Be sure to run `pod lib lint vantiq-ui-ios.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'vantiq-ui-ios'
  s.version          = '0.3.3'
  s.summary          = 'UI API for building Vantiq mobile iOS apps.'
  s.description      = <<-DESC
  UI API for building Vantiq mobile iOS apps to allow cross-platform development.
                       DESC

  s.homepage         = 'https://github.com/Vantiq/vantiq-ui-ios'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Michael Swan' => 'mswan@vantiq.com' }
  s.source           = { :git => 'https://github.com/Vantiq/vantiq-ui-ios.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '12.0'

  s.source_files = 'vantiq-ui-ios/Classes/**/*'
  
  # s.resource_bundles = {
  #   'vantiq-ui-ios' => ['vantiq-ui-ios/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
  s.dependency 'vantiq-sdk-ios', '~> 1.5.1'
  s.dependency 'AppAuth', '~> 1.7.5'
  s.dependency 'JWT', '~> 2.2.0'
  s.dependency 'Base64', '~> 1.1.2'
end
