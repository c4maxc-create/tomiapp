namespace Tomi.BlazorPreview.Models;

// Motion-preview models only. Never read or mutate a TOMI account, wallet or server.
public sealed record Card(string Id, string? Color, string Value)
{
    public string Symbol => Value switch { "skip"=>"⊘", "reverse"=>"⇄", "draw2"=>"+2", "wild4"=>"+4", "wild"=>"✦", _=>Value };
}
public sealed class UnoModel
{
    int serial;
    public List<Card> Hand { get; } = [];
    public Card Top { get; private set; } = new("top","red","7");
    public string ActiveColor { get; private set; } = "red";
    public void Reset()
    {
        Hand.Clear();
        string?[] colors=["red","blue","yellow","green","red",null,"blue"];
        string[] values=["7","2","skip","reverse","draw2","wild4","8"];
        for(int i=0;i<7;i++)Hand.Add(new($"demo-{serial++}",colors[i],values[i]));
        Top=new("top","red","7");ActiveColor="red";
    }
    public Card? Play(string id,string? color=null)
    {
        var card=Hand.Find(c=>c.Id==id);
        if(card is null || card.Color is null&&!new[]{"red","blue","green","yellow"}.Contains(color))return null;
        Hand.Remove(card);Top=card;ActiveColor=card.Color??color!;return card;
    }
    public Card? Draw()
    {
        if(Hand.Count>=12)return null;
        var c=new Card($"demo-{serial++}",new[]{"red","blue","green","yellow"}[Random.Shared.Next(4)],Random.Shared.Next(10).ToString());
        Hand.Add(c);return c;
    }
}
public sealed class SnakeModel
{
    public int Position { get; private set; } = 1;
    public static readonly IReadOnlyDictionary<int,int> Jumps=new Dictionary<int,int>{{2,38},{7,14},{8,31},{15,26},{21,42},{28,84},{36,44},{51,67},{71,91},{78,98},{87,94},{16,6},{46,25},{49,11},{62,19},{64,60},{74,53},{89,68},{92,88},{95,75},{99,80}};
    public bool CanRoll(int dice)=>dice is >=1 and <=6&&Position+dice<=100&&Position<100;
    public void Step(){if(Position<100)Position++;}
    public int Jump(){Position=Jumps.GetValueOrDefault(Position,Position);return Position;}
    public void Reset()=>Position=1;
    public static (double X,double Y) Cell(int n){int row=(n-1)/10,col=(n-1)%10;if(row%2!=0)col=9-col;return ((col+.5)*10,95-row*10);}
}
public sealed class JackModel
{
    public int[] Positions { get; }=[0,6,15,23];
    public int Selected { get; set; }
    public void Reset(){int[] p=[0,6,15,23];Array.Copy(p,Positions,4);Selected=0;}
    public void Step(int pawn,int delta){if(pawn is <0 or >3)throw new ArgumentOutOfRangeException(nameof(pawn));Positions[pawn]=(Positions[pawn]+delta%64+64)%64;}
    public void Swap(){int other=(Selected+1)%4;(Positions[Selected],Positions[other])=(Positions[other],Positions[Selected]);}
    public static (double X,double Y) Cell(int seat,int position){double a=Math.PI/2+((seat*16+position)%64)*Math.PI/32,r=35.5+3.5*Math.Cos(4*a);return (50+Math.Cos(a)*r,50+Math.Sin(a)*r);}
}
public sealed record Tile(int Id,int X,int Y,int Z,int Kind);
public sealed class CamelModel
{
    public static readonly string[] Symbols=["🥕","🧀","🥛","🍀","🧶","🫛","🍰","💎","🌽"];
    public List<Tile> Tiles { get; }=[];
    public List<Tile> Tray { get; }=[];
    public List<Tile> Side { get; }=[];
    public int Matched { get; private set; }
    public bool Lost => Tray.Count>=7;
    public bool Won=>Tiles.Count==0&&Tray.Count==0&&Side.Count==0;
    public int UndoLeft { get; private set; }=1;
    public int StoreLeft { get; private set; }=1;
    public int ShuffleLeft { get; private set; }=1;
    Tile? last;bool lastSide;
    public bool Free(Tile t)=>Tiles.Contains(t)&&!Tiles.Any(b=>b.Z>t.Z&&Math.Abs(b.X-t.X)<2&&Math.Abs(b.Y-t.Y)<2);
    public void Reset()
    {
        Tiles.Clear();Tray.Clear();Side.Clear();Matched=0;last=null;UndoLeft=StoreLeft=ShuffleLeft=1;
        for(int z=0;z<3;z++)for(int y=0;y<(z==0?4:3);y++)for(int x=0;x<(z==2?4:6);x++)Tiles.Add(new(Tiles.Count,x*2+z,y*2+z,z,0));
        var remaining=Tiles.ToList();int n=0;
        while(remaining.Count>0){var free=remaining.Where(t=>!remaining.Any(b=>b.Z>t.Z&&Math.Abs(b.X-t.X)<2&&Math.Abs(b.Y-t.Y)<2)).ToList();var t=free[Random.Shared.Next(free.Count)];Tiles[t.Id]=t with{Kind=n++/3%9};remaining.Remove(t);}
    }
    public bool Pick(int id,bool fromSide=false)
    {
        if(Lost||Won)return false;
        var source=fromSide?Side:Tiles;var t=source.Find(x=>x.Id==id);
        if(t is null||!fromSide&&!Free(t))return false;
        source.Remove(t);Tray.Add(t);last=t;lastSide=fromSide;
        var same=Tray.Where(x=>x.Kind==t.Kind).Take(3).ToList();
        if(same.Count==3){foreach(var x in same)Tray.Remove(x);Matched+=3;last=null;}
        return true;
    }
    public bool Undo()
    {
        if(Lost||UndoLeft==0||last is null||!Tray.Remove(last))return false;
        if(lastSide)Side.Add(last);else Tiles.Add(last);last=null;UndoLeft--;return true;
    }
    public bool Store()
    {
        if(Lost||StoreLeft==0||Side.Count>0||Tray.Count==0)return false;
        var take=Tray.Take(3).ToList();Side.AddRange(take);Tray.RemoveRange(0,take.Count);last=null;StoreLeft--;return true;
    }
    public bool Shuffle()
    {
        if(Lost||ShuffleLeft==0||Tiles.Count<2)return false;
        var kinds=Tiles.Select(t=>t.Kind).ToArray();Random.Shared.Shuffle(kinds);
        for(int i=0;i<Tiles.Count;i++)Tiles[i]=Tiles[i] with{Kind=kinds[i]};last=null;ShuffleLeft--;return true;
    }
}
public sealed class WheelModel
{
    public static readonly string[] Names=["بطيخ","برتقال","تفاح","سلطة","سمك","برغر","روبيان","دجاج"];
    public static readonly string[] Icons=["🍉","🍊","🍎","🥬","🐟","🍔","🍤","🍗"];
    public double Rotation { get; private set; }
    public int Result { get; private set; }=-1;
    public void Spin(int sector)
    {
        if(sector is <0 or >7)throw new ArgumentOutOfRangeException(nameof(sector));
        // CSS conic sectors begin at top; sector centers are at 22.5 + 45*n degrees clockwise.
        double target=(360-(22.5+45*sector))%360;
        Rotation+=1800+(target-Rotation%360+360)%360;Result=sector;
    }
}
