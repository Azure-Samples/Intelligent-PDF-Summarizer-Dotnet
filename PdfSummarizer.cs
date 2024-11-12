using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;
using Microsoft.DurableTask.Client;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using Azure.Identity;
using Azure.AI.FormRecognizer.DocumentAnalysis;
using Newtonsoft.Json;
using System.Net.Http.Headers;
using Microsoft.Azure.Functions.Worker.Extensions.OpenAI;
using Microsoft.Azure.Functions.Worker.Extensions.OpenAI.TextCompletion;
using Azure;

public class DurableFunctionApp
{
    private readonly BlobServiceClient _blobServiceClient;

    public DurableFunctionApp()
    {
        var credential = new DefaultAzureCredential();
        var endpoint = Environment.GetEnvironmentVariable("AzureWebJobsStorage__blobServiceUri");
        _blobServiceClient = new BlobServiceClient(new Uri(endpoint), credential);
    }

    [Function("BlobTrigger")]
    public async Task BlobTrigger(
        [BlobTrigger("input/{name}", Connection = "AzureWebJobsStorage")] ReadOnlyMemory<byte> myBlob,
        string name,
        [DurableClient] DurableTaskClient starter,
        FunctionContext context)
    {
        var logger = context.GetLogger("BlobTrigger");
        logger.LogInformation($"C# Blob trigger function Processed blob\n Name:{name} \n Size: {myBlob.Length} Bytes");

        await starter.ScheduleNewOrchestrationInstanceAsync("ProcessDocument", name);
    }

    [Function("ProcessDocument")]
    public async Task ProcessDocument(
        [OrchestrationTrigger] TaskOrchestrationContext context,
        FunctionContext functionContext)
    {
        var logger = functionContext.GetLogger("ProcessDocument");
        string blobName = context.GetInput<string>();

        var options = TaskOptions.FromRetryPolicy(new RetryPolicy(
            maxNumberOfAttempts: 3,
            firstRetryInterval: TimeSpan.FromSeconds(5)));

        // Ensure the activity function returns a value
        var result = await context.CallActivityAsync<string>("AnalyzePdf", blobName, options);
        var result2 = await context.CallActivityAsync<string>("SummarizeText", result, options );
        var result3 = await context.CallActivityAsync<WriteDocInput>("WriteDoc", new WriteDocInput { BlobName = blobName, Summary = result2 }, options);

        return;
    }

    [Function("AnalyzePdf")]
    public async Task<string> AnalyzePdf([ActivityTrigger] string blobName, FunctionContext context)
    {
        var logger = context.GetLogger("AnalyzePdf");
        logger.LogInformation("In AnalyzePdf activity");

        var containerClient = _blobServiceClient.GetBlobContainerClient("input");
        var blobClient = containerClient.GetBlobClient(blobName);
        var blob = await blobClient.DownloadContentAsync();

        var endpoint = Environment.GetEnvironmentVariable("COGNITIVE_SERVICES_ENDPOINT");
        var credential = new DefaultAzureCredential();
        var documentAnalysisClient = new DocumentAnalysisClient(new Uri(endpoint), credential);
        var modelId = "prebuilt-layout";

        AnalyzeDocumentOperation operation = await documentAnalysisClient.AnalyzeDocumentAsync(WaitUntil.Completed, modelId, blob.Value.Content.ToStream());
        AnalyzeResult result = operation.Value;

        var doc = string.Empty;
        foreach (var page in result.Pages)
        {
            foreach (var line in page.Lines)
            {
                doc += line.Content;
            }
        }

        return doc;
    }

    [Function("SummarizeText")]
    public async Task<string> SummarizeText(
        [ActivityTrigger] string results,
        [TextCompletionInput("Can you explain what the following text is about? {results}", Model = "%CHAT_MODEL_DEPLOYMENT_NAME%")] TextCompletionResponse response,
        FunctionContext context)
    {
        var logger = context.GetLogger("SummarizeText");
        logger.LogInformation("In SummarizeText activity");

        logger.LogInformation(response.Content);
        return response.Content.ToString();
    }

    [Function("WriteDoc")]
    public async Task<string> WriteDoc([ActivityTrigger] WriteDocInput results, FunctionContext context)
    {
        var logger = context.GetLogger("WriteDoc");
        logger.LogInformation("In WriteDoc activity");

        var containerClient = _blobServiceClient.GetBlobContainerClient("output");

        try
        {
            var name = results.BlobName.Replace(".pdf", string.Empty);
            var fileName = $"{name}-summary.txt";

            logger.LogInformation($"Uploading to blob {results.Summary}");

            await containerClient.UploadBlobAsync(fileName, new BinaryData(results.Summary));
            return null;
        }
        catch (Exception ex)
        {
            logger.LogError($"Error uploading to blob: {ex.Message}");
            throw;
        }
    }
}

// Define the WriteDocInput class here
public class WriteDocInput
{
    public string BlobName { get; set; }
    public string Summary { get; set; }
}