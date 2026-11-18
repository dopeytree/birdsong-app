Pod::Spec.new do |s|
  s.name             = 'plate_share'
  s.version          = '0.1.0'
  s.summary          = 'Snapshot the plate web view and share it.'
  s.homepage         = 'https://github.com/dopeytree/birdsong'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Ed Stone' => 'dopeytree@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'plate_share/Sources/plate_share/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.swift_version    = '5.0'
end
