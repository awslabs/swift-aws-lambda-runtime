# with Swift 6.4 or more recent
swift package --allow-network-connections docker lambda-build

-------------------------------------------------------------------------
building "palindrome" in docker
-------------------------------------------------------------------------
updating "swift:6.4-amazonlinux2023" docker image
  amazonlinux2023: Pulling from library/swift
  Digest: sha256:df06a50f70e2e87f237bd904d2fc48195742ebda9f40b4a821c4d39766434009
Status: Image is up to date for swift:amazonlinux2023
  docker.io/library/swift:amazonlinux2023
building "PalindromeLambda"
  [0/1] Planning build
  Building for production...
  [0/2] Write swift-version-24593BA9C3E375BF.txt
  Build of product 'PalindromeLambda' complete! (1.91s)
-------------------------------------------------------------------------
archiving "PalindromeLambda"
-------------------------------------------------------------------------
1 archive created
  * PalindromeLambda at /Users/sst/Palindrome/.build/plugins/AWSLambdaBuilder/outputs/AWSLambdaBuilder/PalindromeLambda/PalindromeLambda.zip
