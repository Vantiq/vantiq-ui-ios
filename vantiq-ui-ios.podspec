#
# Be sure to run `pod lib lint vantiq-ui-ios.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'vantiq-ui-ios'
  s.version          = '0.4.94'
  s.summary          = 'UI API for building Vantiq mobile iOS apps.'
  s.description      = <<-DESC
  UI API for building Vantiq mobile iOS apps to allow cross-platform development.
                       DESC

  s.homepage         = 'https://github.com/Vantiq/vantiq-ui-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Michael Swan' => 'mswan@vantiq.com' }
  s.source           = { :git => 'https://github.com/Vantiq/vantiq-ui-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }

  s.source_files = 'vantiq-ui-ios/**/Classes/*.{h,m}'
  s.public_header_files = 'vantiq-ui-ios/**/Classes/*.h'
 
  s.dependency 'vantiq-sdk-ios'
  s.dependency 'AppAuth', '~> 1.7.5'
  s.dependency 'VantiqJWT', '2.2.0.5'
  s.dependency 'VantiqBase64', '1.2.1.3'
end
