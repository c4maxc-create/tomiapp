Pod::Spec.new do |s|
  s.name = 'tomi_secure'
  s.version = '0.1.0'
  s.summary = 'TOMI vodozemac encryption bridge'
  s.description = 'Small Apache-2.0 bindings to Matrix.org vodozemac.'
  s.homepage = 'https://github.com/ToLo10/tomiapp'
  s.license = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author = { 'TOMI' => 'TOMI' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/tomi_secure.h'
  s.vendored_frameworks = 'Frameworks/TomiSecure.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.static_framework = true
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_tomi_secure_call -Wl,-u,_tomi_secure_free' }
end
