using ERPNextOneClick.Core.ReleaseCatalog;

return CatalogCli.Run(args);

internal static class CatalogCli
{
    private const int UsageError = 2;
    private const int InvalidCatalog = 3;
    private const int PolicyBlocked = 4;

    public static int Run(string[] args)
    {
        if (args.Length < 2 || !string.Equals(args[0], "catalog", StringComparison.OrdinalIgnoreCase))
        {
            PrintUsage();
            return UsageError;
        }

        var command = args[1].ToLowerInvariant();
        var file = ReadOption(args[2..], "--file");
        if (string.IsNullOrWhiteSpace(file))
        {
            Console.Error.WriteLine("The --file <release-catalog.json> option is required.");
            return UsageError;
        }

        ReleaseCatalog catalog;
        try
        {
            catalog = ReleaseCatalogLoader.LoadFromFile(file);
        }
        catch (ReleaseCatalogException exception)
        {
            WriteErrors(exception.Errors);
            return InvalidCatalog;
        }

        return command switch
        {
            "list" => List(catalog),
            "validate" => Validate(catalog),
            "installable" => CheckInstallable(catalog, ReadOption(args[2..], "--id")),
            _ => UnknownCommand(command),
        };
    }

    private static int List(ReleaseCatalog catalog)
    {
        Console.WriteLine($"Catalog status: {catalog.CatalogStatus.ToString().ToLowerInvariant()}");
        foreach (var entry in catalog.Entries.OrderBy(item => item.Id, StringComparer.Ordinal))
        {
            Console.WriteLine($"{entry.Id}\tERPNext v{entry.ErpnextMajor}\t{entry.Status.ToString().ToLowerInvariant()}");
        }

        return 0;
    }

    private static int Validate(ReleaseCatalog catalog)
    {
        Console.WriteLine($"Catalog is structurally valid: schema {catalog.SchemaVersion}, status {catalog.CatalogStatus.ToString().ToLowerInvariant()}, entries {catalog.Entries.Count}.");
        return 0;
    }

    private static int CheckInstallable(ReleaseCatalog catalog, string? releaseId)
    {
        if (string.IsNullOrWhiteSpace(releaseId))
        {
            Console.Error.WriteLine("The --id <release-id> option is required for catalog installable.");
            return UsageError;
        }

        try
        {
            _ = ReleaseCatalogPolicy.RequireInstallable(catalog, releaseId);
            Console.WriteLine($"Release '{releaseId}' is approved for installation.");
            return 0;
        }
        catch (ReleaseCatalogException exception)
        {
            WriteErrors(exception.Errors);
            return PolicyBlocked;
        }
    }

    private static int UnknownCommand(string command)
    {
        Console.Error.WriteLine($"Unknown catalog command '{command}'.");
        PrintUsage();
        return UsageError;
    }

    private static string? ReadOption(IReadOnlyList<string> arguments, string option)
    {
        for (var index = 0; index + 1 < arguments.Count; index++)
        {
            if (string.Equals(arguments[index], option, StringComparison.OrdinalIgnoreCase))
            {
                return arguments[index + 1];
            }
        }

        return null;
    }

    private static void WriteErrors(IEnumerable<string> errors)
    {
        foreach (var error in errors)
        {
            Console.Error.WriteLine($"Error: {error}");
        }
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine("Usage:");
        Console.Error.WriteLine("  ERPNextOneClick.Cli catalog list --file <release-catalog.json>");
        Console.Error.WriteLine("  ERPNextOneClick.Cli catalog validate --file <release-catalog.json>");
        Console.Error.WriteLine("  ERPNextOneClick.Cli catalog installable --id <release-id> --file <release-catalog.json>");
    }
}
