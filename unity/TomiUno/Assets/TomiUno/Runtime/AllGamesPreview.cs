using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;

namespace Tomi.Uno
{
    // An offline Unity motion suite. No auth, wallet, XP or production requests.
    public sealed class AllGamesPreview : MonoBehaviour
    {
        static readonly Color Background=new Color(.035f,.07f,.11f), Surface=new Color(.08f,.16f,.2f), Mint=new Color(.55f,.95f,.77f), Gold=new Color(1,.8f,.4f);
        RectTransform root,content;Font font;Text title,status;
        GameObject uno;bool busy,reduced;
        int snakePosition=1,selectedPawn;int[] jackPositions;
        RectTransform snakePawn;readonly List<RectTransform> jackPawns=new List<RectTransform>();
        RectTransform wheel;
        sealed class Tile {public int Id,Kind,X,Y,Z;}
        readonly List<Tile> tiles=new List<Tile>(),tray=new List<Tile>(),side=new List<Tile>();
        Tile lastTile;bool lastFromSide;int undo=1,remove=1,shuffle=1,matched;
        readonly string[] tileNames={"CARROT","CHEESE","MILK","CLOVER","YARN","PEAS","CAKE","GEM","CORN"};
        readonly string[] fruits={"MELON","ORANGE","APPLE","SALAD","FISH","BURGER","SHRIMP","CHICKEN"};
        void Start()
        {
            Screen.orientation=ScreenOrientation.LandscapeLeft;
            font=Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var cameraObject=new GameObject("Preview background camera",typeof(Camera));cameraObject.transform.SetParent(transform,false);var camera=cameraObject.GetComponent<Camera>();camera.depth=-10;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=Background;
            var canvas=new GameObject("TOMI games preview canvas",typeof(Canvas),typeof(CanvasScaler),typeof(GraphicRaycaster));canvas.transform.SetParent(transform,false);
            canvas.GetComponent<Canvas>().renderMode=RenderMode.ScreenSpaceOverlay;canvas.GetComponent<Canvas>().sortingOrder=500;
            var scale=canvas.GetComponent<CanvasScaler>();scale.uiScaleMode=CanvasScaler.ScaleMode.ScaleWithScreenSize;scale.referenceResolution=new Vector2(1920,1080);scale.screenMatchMode=CanvasScaler.ScreenMatchMode.Expand;
            root=canvas.GetComponent<RectTransform>();
            if(FindFirstObjectByType<EventSystem>()==null)new GameObject("Preview input",typeof(EventSystem),typeof(StandaloneInputModule));
            var backdrop=Box(root,"Backdrop",Vector2.zero,new Vector2(5000,5000),Background);backdrop.GetComponent<Image>().raycastTarget=false;
            content=Box(root,"Current game",Vector2.zero,new Vector2(1920,900),Color.clear);content.GetComponent<Image>().raycastTarget=false;
            title=Label(root,"TOMI PLAY",new Vector2(0,490),32,Gold);
            Button(root,"ALL GAMES",new Vector2(-805,490),new Vector2(230,52),Mint,()=>Open("menu"));
            Button(root,"REDUCE MOTION",new Vector2(770,490),new Vector2(270,52),Gold,()=>{reduced=!reduced;if(uno!=null)uno.GetComponent<UnoTablePreview>().SetReducedMotion(reduced);status.text="Reduced motion: "+reduced;});
            status=Label(root,"LOCAL C# MOTION PREVIEW • No coins or XP",new Vector2(0,-493),20,Color.white);
            Open("menu");
        }
        void Open(string game)
        {
            StopAllCoroutines();busy=false;if(uno!=null)Destroy(uno);uno=null;
            foreach(Transform child in content)Destroy(child.gameObject);
            jackPawns.Clear();content.gameObject.SetActive(game!="uno");
            // The backdrop must not cover the UNO camera's sky/island.
            root.GetChild(0).gameObject.SetActive(game!="uno");
            title.text=game=="menu"?"TOMI PLAY • UNITY / C#":game.ToUpperInvariant()+" • UNITY / C#";
            status.text="LOCAL MOTION PREVIEW • not a live match";status.gameObject.SetActive(game!="uno");
            if(game=="menu")Menu();
            else if(game=="uno"){uno=new GameObject("UNO scene");uno.transform.SetParent(transform);var preview=uno.AddComponent<UnoTablePreview>();preview.SuiteMode=true;preview.SetReducedMotion(reduced);}
            else if(game=="snakes")Snakes();
            else if(game=="jackaroo")Jackaroo();
            else if(game=="camel"){NewTiles();Camel();}
            else Roulette();
        }
        void Menu()
        {
            Label(content,"CHOOSE YOUR TABLE",new Vector2(0,320),40,Color.white);
            var names=new[]{"UNO","SNAKES & LADDERS","JACKAROO","CAMEL MATCH","ROULETTE"};var ids=new[]{"uno","snakes","jackaroo","camel","roulette"};
            for(int i=0;i<ids.Length;i++){string id=ids[i];Button(content,names[i],new Vector2((i%3-1)*490,90-(i/3)*190),new Vector2(440,135),i%2==0?Mint:Gold,()=>Open(id));}
            Label(content,"Every preview is drawn and animated by Unity C#.",new Vector2(0,-330),23,Color.white);
        }
        RectTransform Board(PreviewBoardGraphic.Board kind,Vector2 at,float size)
        {
            var obj=new GameObject(kind+" native board",typeof(RectTransform),typeof(CanvasRenderer),typeof(PreviewBoardGraphic));var rect=obj.GetComponent<RectTransform>();rect.SetParent(content,false);rect.sizeDelta=Vector2.one*size;rect.anchoredPosition=at;obj.GetComponent<PreviewBoardGraphic>().Kind=kind;return rect;
        }
        void Snakes()
        {
            snakePosition=1;var board=Board(PreviewBoardGraphic.Board.Snakes,new Vector2(-180,0),740);
            for(int i=1;i<=100;i++)Label(board,i.ToString(),(PreviewBoardGraphic.SnakeCell(i)-Vector2.one*.5f)*740,16,Color.white);
            snakePawn=Box(board,"Your pawn",(PreviewBoardGraphic.SnakeCell(1)-Vector2.one*.5f)*740,Vector2.one*32,Gold);
            Label(content,"SNAKES & LADDERS",new Vector2(610,240),28,Mint);
            Label(content,"Roll, move cell by cell,\nthen climb or slide.\nExact roll to reach 100.",new Vector2(610,80),25,Color.white);
            Button(content,"ROLL DICE",new Vector2(610,-130),new Vector2(320,85),Mint,()=>{if(!busy)StartCoroutine(Roll());});
            Button(content,"RESET BOARD",new Vector2(610,-245),new Vector2(320,65),Gold,()=>{if(!busy)Open("snakes");});
        }
        IEnumerator Roll()
        {
            busy=true;int dice=Random.Range(1,7);status.text="Demo roll: "+dice;
            if(snakePosition+dice<=100)for(int i=0;i<dice;i++){snakePosition++;yield return Move(snakePawn,(PreviewBoardGraphic.SnakeCell(snakePosition)-Vector2.one*.5f)*740,.13f);}
            int destination=snakePosition==2?38:snakePosition==28?84:snakePosition==16?6:snakePosition==99?80:snakePosition;
            if(destination!=snakePosition){snakePosition=destination;yield return Move(snakePawn,(PreviewBoardGraphic.SnakeCell(snakePosition)-Vector2.one*.5f)*740,.65f);}
            status.text=snakePosition==100?"Preview finish! Reset to play again.":"Demo square "+snakePosition+" • no server turn changed";busy=false;
        }
        void Jackaroo()
        {
            jackPositions=new[]{0,6,15,23};selectedPawn=0;var board=Board(PreviewBoardGraphic.Board.Jackaroo,new Vector2(-200,0),760);
            for(int i=0;i<4;i++){var p=Box(board,"Pawn "+(i+1),(PreviewBoardGraphic.JackCell(0,jackPositions[i])-Vector2.one*.5f)*760,Vector2.one*30,PreviewBoardGraphic.Seats[0]);Label(p,(i+1).ToString(),Vector2.zero,17,Color.white);jackPawns.Add(p);}
            for(int seat=1;seat<4;seat++)for(int i=0;i<4;i++)Box(board,"Other pawn",(PreviewBoardGraphic.JackCell(seat,7+i*5)-Vector2.one*.5f)*760,Vector2.one*26,PreviewBoardGraphic.Seats[seat]);
            Label(content,"JACKAROO • CARD MOTION",new Vector2(600,280),27,Gold);
            Label(content,"Choose a stone and a sample card.\nVisual demonstration, not live rules.",new Vector2(600,175),22,Color.white);
            for(int i=0;i<4;i++){int n=i;Button(content,"PAWN "+(i+1),new Vector2(400+(i%2)*230,50-(i/2)*70),new Vector2(210,55),Mint,()=>{selectedPawn=n;status.text="Selected pawn "+(n+1);});}
            var names=new[]{"A / +1","4 / BACK","7 / SPLIT","J / SWAP","K / +13"};
            for(int i=0;i<5;i++){int n=i;Button(content,names[i],new Vector2(400+(i%2)*230,-120-(i/2)*75),new Vector2(210,58),Gold,()=>{if(!busy)StartCoroutine(JackAction(n));});}
        }
        IEnumerator JackAction(int action)
        {
            busy=true;int pawn=selectedPawn;
            if(action==3)
            {
                int other=(pawn+1)%4,old=jackPositions[pawn];jackPositions[pawn]=jackPositions[other];jackPositions[other]=old;
                yield return Move(jackPawns[other],(PreviewBoardGraphic.JackCell(0,old)-Vector2.one*.5f)*760,.4f);
                yield return Move(jackPawns[pawn],(PreviewBoardGraphic.JackCell(0,jackPositions[pawn])-Vector2.one*.5f)*760,.4f);
            }
            else if(action==2){yield return WalkPawn(pawn,3);yield return WalkPawn((pawn+1)%4,4);}
            else yield return WalkPawn(pawn,action==1?-4:action==4?13:1);
            status.text="Demo card motion • live legality stays on TOMI server";busy=false;
        }
        IEnumerator WalkPawn(int pawn,int steps)
        {
            if(reduced)
            {
                jackPositions[pawn]=(jackPositions[pawn]+steps+64)%64;
                jackPawns[pawn].anchoredPosition=(PreviewBoardGraphic.JackCell(0,jackPositions[pawn])-Vector2.one*.5f)*760;
                yield break;
            }
            for(int i=0;i<Mathf.Abs(steps);i++)
            {
                jackPositions[pawn]=(jackPositions[pawn]+(steps<0?63:1))%64;
                yield return Move(jackPawns[pawn],(PreviewBoardGraphic.JackCell(0,jackPositions[pawn])-Vector2.one*.5f)*760,.1f);
            }
        }
        bool Free(Tile tile){return tiles.Contains(tile)&&!tiles.Exists(t=>t.Z>tile.Z&&Mathf.Abs(t.X-tile.X)<2&&Mathf.Abs(t.Y-tile.Y)<2);}
        void NewTiles()
        {
            tiles.Clear();tray.Clear();side.Clear();lastTile=null;undo=remove=shuffle=1;matched=0;
            for(int z=0;z<3;z++)for(int y=0;y<(z==0?4:3);y++)for(int x=0;x<(z==2?4:6);x++)tiles.Add(new Tile{Id=tiles.Count,X=x*2+z,Y=y*2+z,Z=z});
            var remaining=new List<Tile>(tiles);int n=0;
            while(remaining.Count>0){var free=remaining.FindAll(t=>!remaining.Exists(b=>b.Z>t.Z&&Mathf.Abs(b.X-t.X)<2&&Mathf.Abs(b.Y-t.Y)<2));var t=free[Random.Range(0,free.Count)];t.Kind=(n++/3)%9;remaining.Remove(t);}
        }
        void Camel()
        {
            foreach(Transform child in content)Destroy(child.gameObject);
            Label(content,"CAMEL • MATCH THREE",new Vector2(0,370),31,Gold);
            var board=Box(content,"Layered tile board",new Vector2(-210,15),new Vector2(920,570),new Color(.73f,.59f,.35f));
            foreach(var tile in tiles){var t=tile;bool free=Free(t);Button(board,tileNames[t.Kind],new Vector2(-420+t.X*66,220-t.Y*61),new Vector2(125,112),free?new Color(1,.93f,.73f):new Color(.52f,.56f,.43f),()=>{if(!busy&&Free(t))Pick(t,false);},free);}
            Label(content,"TRAY "+tray.Count+" / 7  •  CLEARED "+matched+" / 54",new Vector2(0,-310),23,Mint);
            for(int i=0;i<tray.Count;i++)Label(content,tileNames[tray[i].Kind],new Vector2(-420+i*140,-375),18,Gold);
            Label(content,"Select uncovered tiles.\nThree equal tiles disappear.\nSeven unmatched tiles ends the demo.",new Vector2(680,200),22,Color.white);
            Button(content,"UNDO ("+undo+")",new Vector2(680,40),new Vector2(300,65),Mint,()=>{if(!busy&&undo>0&&lastTile!=null){tray.Remove(lastTile);if(lastFromSide)side.Add(lastTile);else tiles.Add(lastTile);tiles.Sort((a,b)=>a.Z.CompareTo(b.Z));lastTile=null;undo--;Camel();}});
            Button(content,"STORE 3 ("+remove+")",new Vector2(680,-45),new Vector2(300,65),Gold,()=>{if(!busy&&remove>0&&tray.Count>0&&side.Count==0){int count=Mathf.Min(3,tray.Count);side.AddRange(tray.GetRange(0,count));tray.RemoveRange(0,count);remove--;lastTile=null;Camel();}});
            Button(content,"SHUFFLE ("+shuffle+")",new Vector2(680,-130),new Vector2(300,65),Mint,()=>{if(!busy&&shuffle>0){for(int i=tiles.Count-1;i>0;i--){int j=Random.Range(0,i+1);int kind=tiles[i].Kind;tiles[i].Kind=tiles[j].Kind;tiles[j].Kind=kind;}shuffle--;lastTile=null;Camel();}});
            for(int i=0;i<side.Count;i++){var t=side[i];Button(content,"RETURN "+tileNames[t.Kind],new Vector2(680,-220-i*55),new Vector2(300,48),Gold,()=>{if(!busy)Pick(t,true);});}
            Button(content,"NEW BOARD",new Vector2(-730,-370),new Vector2(260,60),Gold,()=>{NewTiles();busy=false;Camel();});
        }
        void Pick(Tile tile,bool fromSide)
        {
            if(busy||(fromSide?!side.Contains(tile):!Free(tile)))return;
            if(fromSide)side.Remove(tile);else tiles.Remove(tile);tray.Add(tile);lastTile=tile;lastFromSide=fromSide;
            if(tray.FindAll(t=>t.Kind==tile.Kind).Count>=3){int count=0;tray.RemoveAll(t=>t.Kind==tile.Kind&&count++<3);matched+=3;lastTile=null;}
            Camel();
            if(tray.Count>=7){busy=true;status.text="TRAY FULL • start a new board";}
            else if(tiles.Count==0&&tray.Count==0&&side.Count==0)status.text="PREVIEW COMPLETE!";
            else status.text="Matched "+matched+" tiles • offline preview";
        }
        void Roulette()
        {
            wheel=Board(PreviewBoardGraphic.Board.Wheel,new Vector2(-200,0),750);
            for(int i=0;i<8;i++){float a=(90-i*45)*Mathf.Deg2Rad;Label(wheel,fruits[i],new Vector2(Mathf.Cos(a),Mathf.Sin(a))*245,21,Color.white);}
            Label(content,"V",new Vector2(-200,390),40,Gold);
            Label(content,"ROULETTE • MOTION ONLY",new Vector2(610,230),27,Gold);
            Label(content,"Sample a spin and its stop.\nNo stake, no wallet, no prize.",new Vector2(610,80),24,Color.white);
            Button(content,"SPIN PREVIEW",new Vector2(610,-110),new Vector2(340,85),Mint,()=>{if(!busy)StartCoroutine(Spin());});
        }
        IEnumerator Spin()
        {
            busy=true;int result=Random.Range(0,8);float start=wheel.localEulerAngles.z,end=start+1800+Mathf.Repeat(result*45-start,360),time=0,duration=reduced ? .025f : 3.2f;
            while(time<duration){float t=Mathf.Clamp01(time/duration);wheel.localRotation=Quaternion.Euler(0,0,Mathf.Lerp(start,end,1-Mathf.Pow(1-t,4)));time+=Time.unscaledDeltaTime;yield return null;}
            wheel.localRotation=Quaternion.Euler(0,0,end);status.text="DEMO SECTOR: "+fruits[result]+" • no coins changed";busy=false;
        }
        IEnumerator Move(RectTransform rect,Vector2 end,float duration)
        {
            var from=rect.anchoredPosition;float time=0;if(reduced)duration=.025f;
            while(time<duration){float t=Mathf.Clamp01(time/duration);rect.anchoredPosition=Vector2.Lerp(from,end,t*t*(3-2*t));time+=Time.unscaledDeltaTime;yield return null;}rect.anchoredPosition=end;
        }
        RectTransform Box(RectTransform parent,string name,Vector2 at,Vector2 size,Color color)
        {
            var obj=new GameObject(name,typeof(RectTransform),typeof(CanvasRenderer),typeof(Image));var rect=obj.GetComponent<RectTransform>();rect.SetParent(parent,false);rect.sizeDelta=size;rect.anchoredPosition=at;obj.GetComponent<Image>().color=color;return rect;
        }
        Text Label(RectTransform parent,string text,Vector2 at,int size,Color color)
        {
            var obj=new GameObject(text,typeof(RectTransform),typeof(CanvasRenderer),typeof(Text));var t=obj.GetComponent<Text>();t.font=font;t.text=text;t.fontSize=size;t.alignment=TextAnchor.MiddleCenter;t.color=color;t.raycastTarget=false;var rect=obj.GetComponent<RectTransform>();rect.SetParent(parent,false);rect.sizeDelta=new Vector2(1000,130);rect.anchoredPosition=at;return t;
        }
        void Button(RectTransform parent,string name,Vector2 at,Vector2 size,Color color,UnityEngine.Events.UnityAction action,bool enabled=true)
        {
            var rect=Box(parent,name,at,size,color);var button=rect.gameObject.AddComponent<Button>();button.interactable=enabled;button.onClick.AddListener(action);var text=Label(rect,name,Vector2.zero,20,Background);text.rectTransform.sizeDelta=size;
        }
    }
}
