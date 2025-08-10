platform :ios, '14.0'

target 'moai-baby-name-generator' do
  use_frameworks!

  # Facebook SDK Pods
  pod 'FBSDKCoreKit'
  pod 'FBSDKLoginKit'
  
  # Keep your existing dependencies if any
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end