// placeholder — see ../../README.md
namespace Lists.Desktop;

public partial class App
{
    public override void Initialize()
    {
        // AvaloniaXamlLoader.Load(this) — real impl once Avalonia is referenced.
    }

    public override void OnFrameworkInitializationCompleted()
    {
        // Wire main window via classic-desktop lifetime once dependencies exist.
        base.OnFrameworkInitializationCompleted();
    }
}
