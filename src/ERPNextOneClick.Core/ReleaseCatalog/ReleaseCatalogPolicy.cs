namespace ERPNextOneClick.Core.ReleaseCatalog;

public static class ReleaseCatalogPolicy
{
    public static ReleaseCatalogEntry RequireInstallable(ReleaseCatalog catalog, string releaseId)
    {
        var errors = new List<string>();

        if (catalog.CatalogStatus != CatalogStatus.Approved)
        {
            errors.Add("The release catalog is not approved for installation.");
        }

        var entry = catalog.Entries.SingleOrDefault(item => string.Equals(item.Id, releaseId, StringComparison.Ordinal));
        if (entry is null)
        {
            errors.Add($"No release catalog entry exists with id '{releaseId}'.");
        }
        else
        {
            if (entry.Status != ReleaseStatus.Approved)
            {
                errors.Add($"Release '{releaseId}' is not approved for installation.");
            }

            if (entry.Approval is null)
            {
                errors.Add($"Release '{releaseId}' has no approval evidence.");
            }

            if (entry.Images.Erpnext.Digest is null || entry.Images.Mariadb.Digest is null || entry.Images.Redis.Digest is null)
            {
                errors.Add($"Release '{releaseId}' does not pin every container image by digest.");
            }
        }

        if (errors.Count > 0)
        {
            throw new ReleaseCatalogException(errors);
        }

        return entry!;
    }
}
