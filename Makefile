# Makefile for library

format:
	swift format format --parallel --recursive --in-place ./Package*.swift Examples/ Sources/ Tests/ Plugins/

doc-dependency:
	# Dynamically add the swift-docc-plugin for doc generation
	cp Package.swift Package.swift.bak
	for manifest in Package.swift ; do \
		if [ -f "$$manifest" ] && ! grep -E -i "https://github.com/(apple|swiftlang)/swift-docc-plugin" "$$manifest" ; then \
			echo "package.dependencies.append(" >> "$$manifest" ; \
			echo "	.package(url: \"https://github.com/swiftlang/swift-docc-plugin\", from: \"1.4.5\")" >> "$$manifest" ; \
			echo ")" >> "$$manifest" ; \
		fi ; \
	done

preview-docs: doc-dependency
# 	xcrun docc preview Sources/AWSLambdaRuntime/Docs.docc --output-path docc-output
	swift package --disable-sandbox preview-documentation --target AWSLambdaRuntime
	mv Package.swift.bak Package.swift

# swiftpackageindex.com/awslabs/swift-aws-lambda-runtime/~/documentation/awslambdaruntime/
generate-docs: doc-dependency
	touch .nojekyll
	swift package                         \
		--allow-writing-to-directory ./docs \
		generate-documentation              \
		--target BedrockService             \
		--disable-indexing                  \
		--transform-for-static-hosting      \
		--hosting-base-path swift-aws-lambda-runtime \
		--output-path ./docs
	
	mv Package.swift.bak Package.swift

# Run compilation + tests on Linux across Swift toolchains, using Docker.
# Each target uses an isolated --scratch-path so Linux build products don't clash with the
# local (macOS) .build or with each other. `zip` is installed because the ArchiveBackend tests
# shell out to /usr/bin/zip, which is absent from the base images.
DOCKER_RUN = docker run --rm -v "$(CURDIR)":/pkg -w /pkg

.PHONY: test-linux test-linux-6.2 test-linux-6.3 test-linux-6.4

test-linux-6.2:
	$(DOCKER_RUN) swift:6.2-noble \
		bash -c "apt-get update -qq && apt-get install -y -qq zip && swift test --scratch-path .build-linux-6.2"

test-linux-6.3:
	$(DOCKER_RUN) swift:6.3-noble \
		bash -c "apt-get update -qq && apt-get install -y -qq zip && swift test --scratch-path .build-linux-6.3"

test-linux-6.4:
	$(DOCKER_RUN) swiftlang/swift:nightly-6.4.x-bookworm \
		bash -c "apt-get update -qq && apt-get install -y -qq zip && swift test --scratch-path .build-linux-6.4"

# Run all three in sequence.
test-linux: test-linux-6.2 test-linux-6.3 test-linux-6.4
