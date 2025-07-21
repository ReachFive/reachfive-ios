require_relative './version'

Pod::Spec.new do |spec|
  spec.name                  = "Reach5"
  spec.version               = $VERSION
  spec.summary               = "Reachfive Identity SDK"
  spec.description           = <<-DESC
      ReachFive Identity SDK for iOS
  DESC
  spec.homepage              = "https://github.com/ReachFive/reachfive-ios"
  spec.license               = { :type => "MIT", :file => "LICENSE" }
  spec.author                = "ReachFive"
  spec.authors               = { "François" => "francois.devemy@reach5.co", "Pierre" => "pierre.bar@reach5.co" }
  spec.swift_versions        = ["5"]
  spec.source                = { :git => "https://github.com/ReachFive/reachfive-ios.git", :tag => "#{spec.version}" }
  spec.source_files          = "Sources/Core/Classes/**/*.*"
  spec.platform              = :ios
  spec.ios.deployment_target = $IOS_DEPLOYMENT_TARGET
  spec.resource_bundle = {
    'Reach5' => ['Sources/Core/PrivacyInfo.xcprivacy']
  }

  spec.dependency 'CryptoSwift', '~> 1.8'
  spec.dependency 'DeviceKit', '~> 5.1'

end
