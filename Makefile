# Makefile for library

format:
	swift format format --parallel --recursive --in-place ./Package.swift Examples/ Sources/ Tests/

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
