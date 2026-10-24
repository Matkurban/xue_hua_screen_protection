Pod::Spec.new do |s|
  s.name             = 'xue_hua_screen_protection'
  s.version          = '1.0.0'
  s.summary          = 'Cross-platform Flutter screen privacy protection, anti-screenshot, anti-recording, and blur mask plugin.'
  s.description      = <<-DESC
A comprehensive cross-platform Flutter plugin for screen privacy protection, anti-screenshot, anti-recording, capture detection, app-switcher blur masks, and security watermarks.
                       DESC
  s.homepage         = 'https://github.com/Matkurban/xue_hua_screen_protection'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Matkurban' => '3496354336@qq.com' }

  s.source           = { :path => '.' }
  s.source_files = 'xue_hua_screen_protection/Sources/xue_hua_screen_protection/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
