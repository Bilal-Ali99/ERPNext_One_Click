namespace ERPNextOneClick.Core.ReleaseCatalog;

public sealed class ReleaseCatalogException : Exception
{
    public ReleaseCatalogException(IEnumerable<string> errors)
        : base("Release catalog validation failed: " + string.Join(" ", errors))
    {
        Errors = errors.ToArray();
    }

    public IReadOnlyList<string> Errors { get; }
}
