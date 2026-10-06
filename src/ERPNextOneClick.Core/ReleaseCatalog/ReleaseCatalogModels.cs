namespace ERPNextOneClick.Core.ReleaseCatalog;

public enum CatalogStatus
{
    Candidate,
    Approved,
}

public enum ReleaseStatus
{
    Candidate,
    Approved,
    Retired,
}

public sealed record ReleaseCatalog(
    string SchemaVersion,
    CatalogStatus CatalogStatus,
    IReadOnlyList<ReleaseCatalogEntry> Entries);

public sealed record ReleaseCatalogEntry(
    string Id,
    ReleaseStatus Status,
    int ErpnextMajor,
    IReadOnlyList<string> SourceEvidence,
    ComposeSource Compose,
    ReleaseImages Images,
    ReleaseRequirements Requirements,
    IReadOnlyList<string> PromotionChecklist,
    ReleaseApproval? Approval);

public sealed record ComposeSource(
    string Repository,
    string SourceRef,
    string? SourceCommit,
    IReadOnlyList<string> Files);

public sealed record ReleaseImages(
    ImageReference Erpnext,
    ImageReference Mariadb,
    ImageReference Redis);

public sealed record ImageReference(string Repository, string Tag, string? Digest);

public sealed record ReleaseRequirements(
    string Architecture,
    string MinimumWslVersion,
    string? MinimumDockerDesktopVersion);

public sealed record ReleaseApproval(
    string ApprovedOn,
    IReadOnlyList<string> TestedWindowsBuilds,
    string TestedDockerDesktopVersion);
