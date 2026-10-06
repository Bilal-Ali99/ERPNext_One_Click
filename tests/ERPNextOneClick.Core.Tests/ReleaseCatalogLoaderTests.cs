using ERPNextOneClick.Core.ReleaseCatalog;

namespace ERPNextOneClick.Core.Tests;

public sealed class ReleaseCatalogLoaderTests
{
    [Fact]
    public void LoadFromFile_LoadsTheCheckedInCandidateCatalog()
    {
        var catalog = ReleaseCatalogLoader.LoadFromFile(CatalogPath());

        Assert.Equal(CatalogStatus.Candidate, catalog.CatalogStatus);
        Assert.Contains(catalog.Entries, entry => entry.Id == "erpnext-v15-candidate");
        Assert.Contains(catalog.Entries, entry => entry.Id == "erpnext-v16-candidate");
    }

    [Fact]
    public void LoadFromJson_RejectsUnknownProperties()
    {
        const string json = """
            { "schemaVersion": "1.0.0", "catalogStatus": "candidate", "entries": [], "unexpected": true }
            """;

        var exception = Assert.Throws<ReleaseCatalogException>(() => ReleaseCatalogLoader.LoadFromJson(json));

        Assert.Contains(exception.Errors, error => error.Contains("JSON document is invalid", StringComparison.Ordinal));
    }

    [Fact]
    public void RequireInstallable_RejectsCandidateCatalogAndEntry()
    {
        var catalog = ReleaseCatalogLoader.LoadFromFile(CatalogPath());

        var exception = Assert.Throws<ReleaseCatalogException>(
            () => ReleaseCatalogPolicy.RequireInstallable(catalog, "erpnext-v15-candidate"));

        Assert.Contains(exception.Errors, error => error.Contains("catalog is not approved", StringComparison.Ordinal));
        Assert.Contains(exception.Errors, error => error.Contains("is not approved for installation", StringComparison.Ordinal));
    }

    [Fact]
    public void RequireInstallable_RequiresEveryPinnedDigestEvenForAnApprovedEntry()
    {
        var catalog = ReleaseCatalogLoader.LoadFromFile(FixturePath("approved-entry-missing-digest.json"));

        var exception = Assert.Throws<ReleaseCatalogException>(
            () => ReleaseCatalogPolicy.RequireInstallable(catalog, "erpnext-v16-invalid-approved"));

        Assert.Contains(exception.Errors, error => error.Contains("no approval evidence", StringComparison.Ordinal));
        Assert.Contains(exception.Errors, error => error.Contains("does not pin every container image", StringComparison.Ordinal));
    }

    [Fact]
    public void RequireInstallable_AcceptsACompleteApprovedFixture()
    {
        var catalog = ReleaseCatalogLoader.LoadFromFile(FixturePath("approved-entry-complete-fixture.json"));

        var entry = ReleaseCatalogPolicy.RequireInstallable(catalog, "erpnext-v16-approved-fixture");

        Assert.Equal(ReleaseStatus.Approved, entry.Status);
    }

    private static string CatalogPath() => Path.Combine(AppContext.BaseDirectory, "assets", "release-catalog.json");

    private static string FixturePath(string fileName) => Path.Combine(AppContext.BaseDirectory, "fixtures", fileName);
}
