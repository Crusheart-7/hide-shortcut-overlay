# Rebuild the resource DLL

Requires the .NET 8 SDK on Windows. From this `Source` directory:

```powershell
dotnet run --project .\IconResourceBuilder\IconResourceBuilder.csproj -- .\blank-icons.res
dotnet build .\BlankResource\BlankResource.csproj -c Release
```

The output is `BlankResource\bin\Release\net8.0\BlankResource.dll`. It has 198 RT_GROUP_ICON resources, each pointing to six RT_ICON images. Index 197 is group resource ID 198. The pixels are BGRA `00 00 00 01` with a zero AND mask.

For a newly built package, copy the DLL to the package root as `blank-resource.dll`, calculate its SHA-256, and update `ExpectedHash` in `Common.ps1` and the README. The source project is for audit/rebuilding; the ZIP already contains a built and validated DLL.
