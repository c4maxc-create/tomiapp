using System.Globalization;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Tomi.BlazorPreview;
// Geometry and CSS use invariant decimal notation; interface text remains Arabic.
CultureInfo.DefaultThreadCurrentCulture=CultureInfo.InvariantCulture;
var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.Services.AddScoped<Tomi.BlazorPreview.Native.NativeSession>();
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");
await builder.Build().RunAsync();
