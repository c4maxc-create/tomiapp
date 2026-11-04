using Microsoft.AspNetCore.Components;
namespace Tomi.BlazorPreview.Components;
public abstract class PreviewComponent:ComponentBase,IDisposable
{
    [Parameter]public bool ReducedMotion {get;set;}
    protected bool Busy {get;private set;}
    readonly CancellationTokenSource stop=new();
    protected Task Pause(int ms)=>Task.Delay(ReducedMotion?1:ms,stop.Token);
    protected async Task Animate(Func<Task> action)
    {
        if(Busy||stop.IsCancellationRequested)return;
        Busy=true;
        try{await action();}catch(OperationCanceledException) when(stop.IsCancellationRequested){}
        finally{Busy=false;if(!stop.IsCancellationRequested)StateHasChanged();}
    }
    public void Dispose(){stop.Cancel();stop.Dispose();GC.SuppressFinalize(this);}
}
