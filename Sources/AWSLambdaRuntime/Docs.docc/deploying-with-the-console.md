# Deploy with the AWS Console

@Metadata {
    @PageKind(article)
    @PageColor(orange)
    @SupportedLanguage(swift)
    @PageImage(source: "lambda.png", alt: "AWS Lambda", purpose: icon)
}

Upload and test your packaged Swift Lambda function manually through the AWS Console.

## Overview

In this section, we deploy the HelloWorld example function using the AWS Console. The HelloWorld function is a simple function that takes a `String` as input and returns a `String`.

> See <doc:deploying-prerequisites> for the AWS account, credentials, and build steps this article assumes.

Authenticate on the AWS console using your IAM username and password. On the top right side, select the AWS Region where you want to deploy, then navigate to the Lambda section.

![Console - Select AWS Region](console-10-regions)

## Create the function

Select **Create a function** to create a function.

![Console - Lambda dashboard when there is no function](console-20-dashboard)

Select **Author function from scratch**. Enter a **Function name** (`HelloWorld`) and select `Amazon Linux 2023` as **Runtime**.
Select the architecture. When you compile your Swift code on a x84_64 machine, such as an Intel Mac, select `x86_64`. When you compile your Swift code on an Arm machine, such as the Apple Silicon M1 or more recent, select `arm64`.

Select **Create function**

![Console - create function](console-30-create-function)

On the right side, select **Upload from** and select **.zip file**.

![Console - select zip file](console-40-select-zip-file)

Select the zip file created with the `swift package lambda-build` command as described in <doc:deploying-prerequisites>.

Select **Save**

![Console - select zip file](console-50-upload-zip)

You're now ready to test your function.

## Invoke the function

Select the **Test** tab in the console and prepare a payload to send to your Lambda function. In this example, you've deployed the [HelloWorld](https://github.com/awslabs/swift-aws-lambda-runtime/tree/main/Examples/HelloWorld) example function. As explained, the function takes a `String` as input and returns a `String`. we will therefore create a test event with a JSON payload that contains a `String`.

Select **Create new event**. Enter an **Event name**. Enter `"Swift on Lambda"` as **Event JSON**. Note that the payload must be a valid JSON document, hence we use surrounding double quotes (`"`).

Select **Test** on the upper right side of the screen.

![Console - prepare test event](console-60-prepare-test-event)

The response of the invocation and additional meta data appear in the green section of the page.

You can see the response from the Swift code: `Hello Swift on Lambda`.

The function consumed 109.60ms of execution time, out of this 83.72ms where spent to initialize this new runtime. This initialization time is known as Lambda cold start time.

> Lambda cold start time refers to the initial delay that occurs when a Lambda function is invoked for the first time or after being idle for a while. Cold starts happen because AWS needs to provision and initialize a new container, load your code, and start your runtime environment (in this case, the Swift runtime). This delay is particularly noticeable for the first invocation, but subsequent invocations (known as "warm starts") are typically much faster because the container and runtime are already initialized and ready to process requests. Cold starts are an important consideration when architecting serverless applications, especially for latency-sensitive workloads. Usually, compiled languages, such as Swift, Go, and Rust, have shorter cold start times compared to interpreted languages, such as Python, Java, Ruby, and Node.js.

![Console - view invocation result](console-70-view-invocation-response)

Select **Test** to invoke the function again with the same payload.

Observe the results. No initialization time is reported because the Lambda execution environment was ready after the first invocation. The runtime duration of the second invocation is 1.12ms.

```text
REPORT RequestId: f789fbb6-10d9-4ba3-8a84-27aa283369a2	Duration: 1.12 ms	Billed Duration: 2 ms	Memory Size: 128 MB	Max Memory Used: 26 MB	
```

AWS lambda charges usage per number of invocations and the CPU time, rounded to the next millisecond. AWS Lambda offers a generous free-tier of 1 million invocation each month and 400,000 GB-seconds of compute time per month. See [Lambda pricing](https://aws.amazon.com/lambda/pricing/) for the details.

## Delete the function

When you're finished with testing, you can delete the Lambda function and the IAM execution role that the console created automatically.

While you are on the `HelloWorld` function page in the AWS console, select **Actions**, then **Delete function** in the menu on the top-right part of the page.

![Console - delete function](console-80-delete-function)

Then, navigate to the IAM section of the AWS console. Select **Roles** on the right-side menu and search for `HelloWorld`. The console appended some random characters to role name. The name you see on your console is different that the one on the screenshot.

Select the `HelloWorld-role-xxxx` role and select **Delete**. Confirm the deletion by entering the role name again, and select **Delete** on the confirmation box.

![Console - delete IAM role](console-80-delete-role)
