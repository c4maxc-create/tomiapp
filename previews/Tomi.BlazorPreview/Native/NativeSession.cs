using System.Text.Json;
using Microsoft.JSInterop;
namespace Tomi.BlazorPreview.Native;
public static class JsonView
{
    public static JsonElement Get(this JsonElement e,string key)=>e.ValueKind==JsonValueKind.Object&&e.TryGetProperty(key,out var v)?v:default;
    public static string Text(this JsonElement e,string key,string fallback="")=>e.Get(key).ValueKind==JsonValueKind.String?e.Get(key).GetString()!:fallback;
    public static int Num(this JsonElement e,string key,int fallback=0)=>e.Get(key).TryNumber(fallback);
    public static int TryNumber(this JsonElement e,int fallback=0)=>e.ValueKind==JsonValueKind.Number&&e.TryGetInt32(out int n)?n:fallback;
    public static bool Yes(this JsonElement e,string key)=>e.Get(key).ValueKind==JsonValueKind.True;
    public static JsonElement[] Items(this JsonElement e)=>e.ValueKind==JsonValueKind.Array?e.EnumerateArray().ToArray():[];
    public static bool Exists(this JsonElement e)=>e.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined);
}
// Transport only: the authenticated native controller remains the authority for requests,
// durable retry, account lifecycle and revision checks. No tokens enter WebAssembly.
public sealed class NativeSession(IJSRuntime js):IAsyncDisposable
{
    DotNetObjectReference<NativeSession>? reference;
    public JsonElement State{get;private set;}
    public JsonElement Match=>State.Get("match");
    public JsonElement Roulette=>State.Get("roulette");
    public bool Waiting{get;private set;}
    public bool Connected=>State.Yes("current");
    public bool CanAct=>Connected&&State.Yes("canAct")&&!Waiting;
    public bool MyTurn=>CanAct&&Match.Text("status")=="playing"&&(Match.Text("kind")=="camel"||Match.Num("turn")==Match.Num("mySeat"));
    public string? TransportError{get;private set;}
    public event Action? Changed;
    public event Action? ClockChanged;
    public long RouletteNow{get;private set;}
    string? inFlight;
    public async Task Connect(){reference=DotNetObjectReference.Create(this);await js.InvokeVoidAsync("tomiNative.connect",reference);}
    [JSInvokable]public void Receive(JsonElement value)
    {
        if(value.Get("rouletteNow").ValueKind==JsonValueKind.Number)RouletteNow=value.Get("rouletteNow").GetInt64();
        if(value.Yes("clock")){ClockChanged?.Invoke();return;}
        State=value;
        if(inFlight is not null&&value.Text("ack")==inFlight){Waiting=false;inFlight=null;}
        Changed?.Invoke();
    }
    public async Task Send(string command,object? args=null)
    {
        if(Waiting)return;
        Waiting=true;TransportError=null;inFlight=Guid.NewGuid().ToString("N");Changed?.Invoke();
        try{await js.InvokeVoidAsync("tomiNative.send",new{id=inFlight,command,args,matchId=Match.Text("id"),revision=Match.Num("revision"),roundId=Roulette.Text("roundId")});}
        catch(JSException){Waiting=false;inFlight=null;TransportError="تعذّر الاتصال بالتطبيق. أعد فتح قسم الألعاب.";Changed?.Invoke();}
    }
    public async ValueTask DisposeAsync(){try{await js.InvokeVoidAsync("tomiNative.disconnect");}catch(JSDisconnectedException){}reference?.Dispose();}
}
