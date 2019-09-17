require_relative './version'

Pod::Spec.new do |spec|
  spec.name                  = "IdentitySdkFacebook"
  spec.version               = $VERSION
  spec.summary               = "ReachFive IdentitySdkFacebook"
  spec.description           = <<-DESC
      ReachFive Identity Sdk Facebook
  DESC
  spec.homepage              = "https://github.com/ReachFive/identity-ios-sdk"
  spec.license               = { :type => "MIT", :file => "LICENSE" }
  spec.author                = "ReachFive"
  spec.authors               = { "egor" => "egor@reach5.co" }
  spec.swift_versions        = ["5"]
  spec.source                = { :git => "https://github.com/ReachFive/identity-ios-sdk.git", :tag => "#{spec.version}" }
  spec.source_files          = "IdentitySdkFacebook/IdentitySdkFacebook/Classes/**/*.*"
  spec.platform              = :ios
  spec.ios.deployment_target = $IOS_DEPLOYMENT_TARGET

  spec.dependency 'IdentitySdkCore', '~> 5.1'
  spec.dependency 'FacebookCore', '~> 0.9'
  spec.dependency 'FacebookLogin', '~> 0.9'
end
