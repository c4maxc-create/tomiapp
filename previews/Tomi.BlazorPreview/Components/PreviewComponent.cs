using Microsoft.AspNetCore.Components;
namespace Tomi.BlazorPreview.Components;
public abstract class PreviewComponent:ComponentBase,IDisposable
{
    [Parameter]public double AnimationSpeed {get;set;}=1;
    [Parameter]public bool ReducedMotion {get;set;}
    protected bool Busy {get;private set;}
    protected bool Disposed=>stop.IsCancellationRequested;
    readonly CancellationTokenSource stop=new();
    protected Task Pause(int ms)=>Task.Delay(ReducedMotion?1:(int)(ms/Math.Clamp(AnimationSpeed,.5,2)),stop.Token);
    protected async Task Animate(Func<Task> action)
    {
        if(Busy||stop.IsCancellationRequested)return;
        Busy=true;
        try{await action();}catch(OperationCanceledException) when(stop.IsCancellationRequested){}
        finally{Busy=false;if(!stop.IsCancellationRequested)StateHasChanged();}
    }
    public void Dispose(){stop.Cancel();stop.Dispose();GC.SuppressFinalize(this);}
}
