using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace SampleApi.Tests;

public class ApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public ApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task HealthEndpoint_ReturnsSuccess()
    {
        var response = await _client.GetAsync("/sample-api/healthz");
        response.EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task HelloEndpoint_ReturnsExpectedMessage()
    {
        var response = await _client.GetStringAsync("/sample-api/api/hello");
        Assert.Contains("Hello from Jenkins", response);
    }
}
