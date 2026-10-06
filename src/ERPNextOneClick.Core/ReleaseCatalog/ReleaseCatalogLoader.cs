using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace ERPNextOneClick.Core.ReleaseCatalog;

public static partial class ReleaseCatalogLoader
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static ReleaseCatalog LoadFromFile(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new ReleaseCatalogException(["A release catalog file path is required."]);
        }

        try
        {
            return LoadFromJson(File.ReadAllText(path));
        }
        catch (IOException exception)
        {
            throw new ReleaseCatalogException([$"Could not read '{path}': {exception.Message}"]);
        }
        catch (UnauthorizedAccessException exception)
        {
            throw new ReleaseCatalogException([$"Could not access '{path}': {exception.Message}"]);
        }
    }

    public static ReleaseCatalog LoadFromJson(string json)
    {
        ReleaseCatalog? catalog;

        try
        {
            catalog = JsonSerializer.Deserialize<ReleaseCatalog>(json, SerializerOptions);
        }
        catch (JsonException exception)
        {
            throw new ReleaseCatalogException([$"The JSON document is invalid: {exception.Message}"]);
        }

        if (catalog is null)
        {
            throw new ReleaseCatalogException(["The JSON document does not contain a release catalog."]);
        }

        var errors = ValidateStructure(catalog);
        if (errors.Count > 0)
        {
            throw new ReleaseCatalogException(errors);
        }

        return catalog;
    }

    private static List<string> ValidateStructure(ReleaseCatalog catalog)
    {
        var errors = new List<string>();

        if (!string.Equals(catalog.SchemaVersion, "1.0.0", StringComparison.Ordinal))
        {
            errors.Add("schemaVersion must be '1.0.0'.");
        }

        if (catalog.Entries is null || catalog.Entries.Count == 0)
        {
            errors.Add("entries must contain at least one release.");
            return errors;
        }

        var knownIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in catalog.Entries)
        {
            ValidateEntry(entry, knownIds, errors);
        }

        return errors;
    }

    private static void ValidateEntry(ReleaseCatalogEntry entry, ISet<string> knownIds, ICollection<string> errors)
    {
        if (entry is null)
        {
            errors.Add("entries cannot contain null values.");
            return;
        }

        var prefix = $"Entry '{entry.Id}':";
        if (!ReleaseIdPattern().IsMatch(entry.Id))
        {
            errors.Add($"{prefix} id must follow erpnext-v15/16-<name>.");
        }
        else if (!knownIds.Add(entry.Id))
        {
            errors.Add($"{prefix} id is duplicated.");
        }

        if (entry.ErpnextMajor is not (15 or 16))
        {
            errors.Add($"{prefix} erpnextMajor must be 15 or 16.");
        }

        if (entry.SourceEvidence is null || entry.SourceEvidence.Count == 0 || entry.SourceEvidence.Any(value => !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps))
        {
            errors.Add($"{prefix} sourceEvidence must contain HTTPS URLs.");
        }

        if (entry.Compose is null || !string.Equals(entry.Compose.Repository, "frappe/frappe_docker", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(entry.Compose.SourceRef) || entry.Compose.Files is null || entry.Compose.Files.Count < 3)
        {
            errors.Add($"{prefix} compose metadata is incomplete.");
        }
        else if (entry.Compose.SourceCommit is not null && !ShaPattern().IsMatch(entry.Compose.SourceCommit))
        {
            errors.Add($"{prefix} compose.sourceCommit must be a 40-character lowercase SHA.");
        }

        if (entry.Images is null)
        {
            errors.Add($"{prefix} images metadata is missing.");
        }
        else
        {
            ValidateImage(entry.Images.Erpnext, "erpnext", prefix, errors);
            ValidateImage(entry.Images.Mariadb, "mariadb", prefix, errors);
            ValidateImage(entry.Images.Redis, "redis", prefix, errors);
        }

        if (entry.Requirements is null || !string.Equals(entry.Requirements.Architecture, "x64", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(entry.Requirements.MinimumWslVersion))
        {
            errors.Add($"{prefix} requirements must declare x64 and a minimum WSL version.");
        }

        if (entry.PromotionChecklist is null || entry.PromotionChecklist.Count == 0 || entry.PromotionChecklist.Any(string.IsNullOrWhiteSpace))
        {
            errors.Add($"{prefix} promotionChecklist must not be empty.");
        }
    }

    private static void ValidateImage(ImageReference? image, string name, string prefix, ICollection<string> errors)
    {
        if (image is null)
        {
            errors.Add($"{prefix} images.{name} metadata is missing.");
            return;
        }

        if (string.IsNullOrWhiteSpace(image.Repository) || string.IsNullOrWhiteSpace(image.Tag))
        {
            errors.Add($"{prefix} images.{name} needs a repository and tag.");
        }

        if (image.Digest is not null && !DigestPattern().IsMatch(image.Digest))
        {
            errors.Add($"{prefix} images.{name}.digest is not a valid SHA-256 digest.");
        }
    }

    [GeneratedRegex("^erpnext-v(15|16)-[a-z0-9-]+$")]
    private static partial Regex ReleaseIdPattern();

    [GeneratedRegex("^[a-f0-9]{40}$")]
    private static partial Regex ShaPattern();

    [GeneratedRegex("^sha256:[a-f0-9]{64}$")]
    private static partial Regex DigestPattern();
}
