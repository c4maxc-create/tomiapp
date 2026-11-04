using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;

namespace Tomi.Uno
{
    public sealed class UnoTablePreview : MonoBehaviour
    {
        [SerializeField] bool designSandbox = true;
        [SerializeField] bool reducedMotion;
        public event Action<ActionIntent> ActionRequested;
        public bool SuiteMode { get; set; }
        public void SetReducedMotion(bool enabled)
        {
            reducedMotion=enabled;
            if(message!=null)message.text="Reduced motion: "+enabled;
        }
        readonly SnapshotGate gate = new SnapshotGate();
        readonly List<RectTransform> hand = new List<RectTransform>();
        readonly List<Material> sceneMaterials = new List<Material>();
        readonly List<CardState> demoCards = new List<CardState>();
        RectTransform root, flightLayer, discardCard;
        Text message, turnLabel;
        Font font;
        Sprite rounded;
        int selected = -1, demoSerial;
        bool busy, announce;
        string chosenColor = "red";
        ActionIntent pending;
        RectTransform colorPanel;
        static readonly Color Ink = new Color(.04f, .065f, .11f);
        static readonly Color Mint = new Color(.35f, 1, .77f);
        static readonly Color Gold = new Color(1, .78f, .36f);

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Launch()
        {
            if (FindFirstObjectByType<UnoTablePreview>() == null && FindFirstObjectByType<AllGamesPreview>() == null)
                new GameObject("TOMI games preview").AddComponent<AllGamesPreview>();
        }
        void Start()
        {
            Screen.orientation = ScreenOrientation.LandscapeLeft;
            font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            rounded = RoundedSprite();
            BuildTable(); BuildHud();
            if (designSandbox) StartCoroutine(Deal());
            else message.text = "Waiting for an authenticated TOMI snapshot";
        }
        void BuildTable()
        {
            var cameraObject = new GameObject("Table camera");
            cameraObject.transform.SetParent(transform,false);
            var camera = cameraObject.AddComponent<Camera>();
            camera.transform.position = new Vector3(0, 10, -8);
            camera.transform.LookAt(Vector3.zero);
            camera.orthographic = true; camera.orthographicSize = Mathf.Max(6.3f, 9f / camera.aspect);
            camera.clearFlags = CameraClearFlags.SolidColor; camera.backgroundColor = new Color(.16f,.72f,.87f);
            Mesh("Floating walnut rail", PrimitiveType.Cylinder, new Vector3(0,-.18f,0), new Vector3(7.9f,.2f,5.4f), new Color(.36f,.27f,.12f));
            Mesh("Champagne metal rim", PrimitiveType.Cylinder, new Vector3(0,.02f,0), new Vector3(7.65f,.06f,5.15f), Gold);
            Mesh("Deep jade felt", PrimitiveType.Cylinder, new Vector3(0,.1f,0), new Vector3(7.5f,.07f,5f), new Color(.31f,.64f,.14f));
            // Low-poly scenery belongs to the actual Unity scene, not a mock web background.
            for(int i=0;i<10;i++)
            {
                float a=i*Mathf.PI*2/10;
                Mesh("Island stone "+i,PrimitiveType.Cube,new Vector3(Mathf.Cos(a)*6.6f,-.65f,Mathf.Sin(a)*4.1f),new Vector3(2.1f,1.25f,1.6f),new Color(.35f,.29f,.17f));
            }
            for(int i=0;i<6;i++)
            {
                float a=(i+.35f)*Mathf.PI*2/6;
                var at=new Vector3(Mathf.Cos(a)*6.2f,.7f,Mathf.Sin(a)*3.8f);
                Mesh("Tree trunk "+i,PrimitiveType.Cylinder,at,new Vector3(.13f,.55f,.13f),new Color(.45f,.3f,.12f));
                Mesh("Tree canopy "+i,PrimitiveType.Sphere,at+Vector3.up*.7f,new Vector3(.9f,1.2f,.9f),new Color(.12f,.48f,.17f));
            }
            var light = new GameObject("Soft key light").AddComponent<Light>();
            light.transform.SetParent(transform,false);
            light.type = LightType.Directional; light.intensity = 1.25f;
            light.transform.rotation = Quaternion.Euler(55,-25,0);
            RenderSettings.ambientLight = new Color(.45f,.5f,.6f);
        }
        void Mesh(string label, PrimitiveType shape, Vector3 at, Vector3 size, Color color)
        {
            var obj = GameObject.CreatePrimitive(shape); obj.name = label;
            obj.transform.SetParent(transform); obj.transform.position = at; obj.transform.localScale = size;
            Destroy(obj.GetComponent<Collider>());
            var template=Resources.Load<Material>("TomiPreviewSurface");
            var material=template!=null?new Material(template):new Material(Shader.Find("Standard"));
            sceneMaterials.Add(material);material.color = color;
            material.SetFloat("_Glossiness", .3f); obj.GetComponent<Renderer>().material = material;
        }
        void BuildHud()
        {
            var canvas = new GameObject("Responsive table HUD", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvas.transform.SetParent(transform);
            canvas.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvas.GetComponent<CanvasScaler>(); scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920,1080); scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.Expand;
            root = canvas.GetComponent<RectTransform>();
            if (FindFirstObjectByType<EventSystem>() == null)
                new GameObject("Pointer input", typeof(EventSystem), typeof(StandaloneInputModule));
            if(!SuiteMode)Label(root,"TOMI  /  PLAY",new Vector2(-680,445),32,Ink);
            if(!SuiteMode)Label(root,designSandbox?"UNO • MOTION DESIGN SANDBOX":"UNO • HOST ADAPTER / NOT CONNECTED",new Vector2(490,445),20,Ink);
            Label(root,"CARD CLUB",new Vector2(0,185),16,new Color(.65f,.8f,.73f));
            turnLabel = Label(root,"YOUR TABLE. YOUR MOMENT.",new Vector2(0,225),24,Color.white);
            Seat("KATIE",new Vector2(0,350),"07",Gold);
            Seat("OMAR",new Vector2(-670,15),"07",Mint);
            Seat("LINA",new Vector2(670,15),"07",new Color(.55f,.7f,1));
            Label(root,"YOU  •  LEVEL 12",new Vector2(0,-435),21,Gold);
            var deck = Card(root,null,new Vector2(-110,15)); deck.localEulerAngles = new Vector3(0,0,8);
            deck.gameObject.AddComponent<Button>().onClick.AddListener(Draw);
            discardCard=Card(root,designSandbox?new CardState {id="top",color="red",value="7"}:null,new Vector2(110,15));
            Label(root,"DRAW PILE",new Vector2(-110,-115),14,Color.white);
            Label(root,"IN PLAY",new Vector2(110,-115),14,Color.white);
            message = Label(root,"Select a card, then PLAY. Demo only; no coins or XP.",new Vector2(0,-480),18,Color.white);
            Button(root,"PLAY CARD",new Vector2(620,-340),new Vector2(245,70),Mint,Play);
            Button(root,"DRAW",new Vector2(-620,-340),new Vector2(200,70),Color.white,Draw);
            Button(root,"UNO!",new Vector2(620,-430),new Vector2(245,70),Gold,()=>{announce=!announce;message.text=announce?"UNO announced for your next play":"UNO announcement off";});
            Button(root,"DEAL AGAIN",new Vector2(-700,380),new Vector2(220,54),Gold,()=>{if(designSandbox&&!busy)StartCoroutine(Deal());});
            if(!SuiteMode)Button(root,"REDUCE MOTION",new Vector2(680,380),new Vector2(250,54),Color.white,()=>{reducedMotion=!reducedMotion;message.text="Reduced motion: "+reducedMotion;});
            if (designSandbox)
            {
                Button(root,"REVERSE",new Vector2(-360,-190),new Vector2(200,52),Gold,()=>Effect("REVERSE",Gold));
                Button(root,"SKIP",new Vector2(-120,-190),new Vector2(180,52),Gold,()=>Effect("SKIP",Gold));
                Button(root,"+2",new Vector2(100,-190),new Vector2(160,52),Mint,()=>Effect("DRAW +2",Mint));
                Button(root,"+4",new Vector2(300,-190),new Vector2(160,52),Gold,()=>Effect("DRAW +4",Gold));
            }
            flightLayer = Panel(root,"Animation layer",Vector2.zero,new Vector2(1920,1080),Color.clear);
            flightLayer.GetComponent<Image>().raycastTarget=false;
            colorPanel=Panel(root,"Choose wild color",new Vector2(0,80),new Vector2(660,200),Ink);
            Label(colorPanel,"CHOOSE A COLOR",new Vector2(0,55),20,Color.white);
            var colors=new[]{"red","yellow","green","blue"};
            for(var i=0;i<colors.Length;i++) {var color=colors[i];Button(colorPanel,color.ToUpperInvariant(),new Vector2(-240+i*160,-25),new Vector2(145,65),CardColor(color),()=>{chosenColor=color;colorPanel.gameObject.SetActive(false);SubmitPlay();});}
            colorPanel.gameObject.SetActive(false);
        }
        IEnumerator Deal()
        {
            busy=true; ClearHand(); demoCards.Clear(); selected=-1;
            foreach(Transform child in flightLayer)Destroy(child.gameObject);
            var colors=new[]{"red","blue","yellow","green","red",null,"blue"};
            var values=new[]{"7","2","skip","reverse","draw2","wild4","8"};
            for(int i=0;i<7;i++)
            {
                demoCards.Add(new CardState{id="demo-"+(demoSerial++),color=colors[i],value=values[i]});
                var card=Card(root,demoCards[i],new Vector2(-110,15),reducedMotion); hand.Add(card);
                int index=i;card.gameObject.AddComponent<Button>().onClick.AddListener(()=>Select(index));
                yield return Fly(card,HandPoint(i,7),HandAngle(i,7),.30f,true);
                foreach(var target in new[]{new Vector2(0,350),new Vector2(-670,15),new Vector2(670,15)})
                {
                    var back=Card(root,null,new Vector2(-110,15));
                    back.localScale=Vector3.one*.6f;
                    yield return Fly(back,target,0,.12f);
                    Destroy(back.gameObject);
                }
            }
            busy=false; message.text="Design sandbox • select any card to preview its motion";
        }
        Vector2 HandPoint(int i,int count) {float x=(i-(count-1)*.5f)*Mathf.Min(94,660f/Mathf.Max(1,count));return new Vector2(x,-295-Mathf.Abs(x)*.075f);}
        float HandAngle(int i,int count) {return -(i-(count-1)*.5f)*5;}
        void Select(int index)
        {
            if(busy||index<0||index>=hand.Count)return;
            selected=index;
            for(int i=0;i<hand.Count;i++)
            {
                hand[i].anchoredPosition=HandPoint(i,hand.Count)+(i==selected?new Vector2(0,48):Vector2.zero);
                hand[i].localScale=Vector3.one*(i==selected?1.1f:1);
            }
            hand[index].SetAsLastSibling(); flightLayer.SetAsLastSibling();colorPanel.SetAsLastSibling();
            message.text="Selected "+(designSandbox?demoCards[index].Symbol:gate.Current.hand[index].Symbol);
        }
        void Play()
        {
            if(busy||pending!=null||selected<0){message.text=pending!=null?"Awaiting acknowledgement; retry the same request via host":"Select a card first";return;}
            var card=designSandbox?demoCards[selected]:gate.Current?.hand[selected];
            if(card==null)return;
            if(!designSandbox&&!gate.CanPlay(card.id)){message.text="This card is not playable in the current server state";return;}
            if(card.color==null){colorPanel.SetAsLastSibling();colorPanel.gameObject.SetActive(true);return;}
            SubmitPlay();
        }
        void SubmitPlay()
        {
            if(designSandbox)StartCoroutine(DemoPlay());
            else Request("play",gate.Current.hand[selected]);
        }
        IEnumerator DemoPlay()
        {
            busy=true;int index=selected;var card=hand[index];var data=demoCards[index];
            card.SetParent(flightLayer,false);card.localScale=Vector3.one;
            yield return Fly(card,new Vector2(110,15),-9,.45f);
            hand.RemoveAt(index);demoCards.RemoveAt(index);selected=-1;
            // Keep one visible discard. Older flights must not accumulate.
            foreach(Transform old in flightLayer)if(old!=card)Destroy(old.gameObject);
            for(int i=0;i<hand.Count;i++){int n=i;hand[i].GetComponent<Button>().onClick.RemoveAllListeners();hand[i].GetComponent<Button>().onClick.AddListener(()=>Select(n));hand[i].anchoredPosition=HandPoint(i,hand.Count);hand[i].localEulerAngles=new Vector3(0,0,HandAngle(i,hand.Count));hand[i].localScale=Vector3.one;}
            if(data.value=="reverse"||data.value=="skip"||data.value=="draw2"||data.color==null)Effect(data.color==null?"COLOR • "+chosenColor.ToUpperInvariant():data.Symbol,CardColor(data.color??chosenColor));
            message.text="Motion preview • no server turn was changed";busy=false;
        }
        void Draw()
        {
            if(busy||pending!=null)return;
            if(!designSandbox){if(gate.Current!=null&&gate.Current.canDraw&&gate.Current.turn==gate.Current.mySeat)Request("draw",null);return;}
            if(hand.Count>=12){message.text="Preview hand limit reached • deal again";return;}
            StartCoroutine(DemoDraw());
        }
        IEnumerator DemoDraw()
        {
            busy=true;var data=new CardState{id="demo-"+(demoSerial++),color="green",value="5"};
            demoCards.Add(data);var card=Card(root,data,new Vector2(-110,15),reducedMotion);hand.Add(card);
            for(int i=0;i<hand.Count-1;i++){hand[i].anchoredPosition=HandPoint(i,hand.Count);hand[i].localEulerAngles=new Vector3(0,0,HandAngle(i,hand.Count));}
            yield return Fly(card,HandPoint(hand.Count-1,hand.Count),HandAngle(hand.Count-1,hand.Count),.45f,true);
            int index=hand.Count-1;card.gameObject.AddComponent<Button>().onClick.AddListener(()=>Select(index));busy=false;
        }
        void Request(string type,CardState card)
        {
            if(gate.Current==null||ActionRequested==null){message.text="Host transport is not connected";return;}
            pending=new ActionIntent{requestId=Guid.NewGuid().ToString(),type=type,revision=gate.Current.revision,cardId=card?.id,color=card?.color==null&&card!=null?chosenColor:null,uno=announce};
            ActionRequested.Invoke(pending);message.text="Waiting for server acknowledgement";
        }
        public void RetryPending() {if(pending!=null)ActionRequested?.Invoke(pending);}
        public bool ApplyServerSnapshot(string json)
        {
            if(designSandbox)return false;
            var next=JsonUtility.FromJson<TableSnapshot>(json);
            if(!gate.Accept(next))return false;
            StopAllCoroutines();busy=false;ClearHand();selected=-1;
            foreach(var data in next.hand??Array.Empty<CardState>())
            {
                int i=hand.Count;var card=Card(root,data,HandPoint(i,next.hand.Length));hand.Add(card);
                card.localEulerAngles=new Vector3(0,0,HandAngle(i,next.hand.Length));card.gameObject.AddComponent<Button>().onClick.AddListener(()=>Select(i));
            }
            if(discardCard!=null)Destroy(discardCard.gameObject);
            discardCard=Card(root,next.topCard,new Vector2(110,15));
            flightLayer.SetAsLastSibling();colorPanel.SetAsLastSibling();
            turnLabel.text=next.turn==next.mySeat?"YOUR TURN":"WAITING FOR PLAYER "+(next.turn+1);
            message.text="Server state • revision "+next.revision;
            return true;
        }
        // Host calls only after a matching accepted receipt or definitive rejection.
        public void ResolvePending(string requestId) {if(pending?.requestId==requestId)pending=null;}
        public void ClearSession()
        {
            StopAllCoroutines();gate.Clear();pending=null;selected=-1;busy=false;ClearHand();
            if(flightLayer!=null)foreach(Transform child in flightLayer)Destroy(child.gameObject);
            if(colorPanel!=null)colorPanel.gameObject.SetActive(false);
            if(message!=null)message.text="Session cleared";
        }
        void ClearHand(){foreach(var card in hand)if(card!=null)Destroy(card.gameObject);hand.Clear();}
        IEnumerator Fly(RectTransform card,Vector2 end,float angle,float seconds,bool reveal=false)
        {
            var begin=card.anchoredPosition;var rotation=card.localRotation;var scale=card.localScale;var view=card.GetComponent<UnoCardReveal>();float time=0;
            float duration=reducedMotion ? 0.025f : seconds;
            while(time<duration)
            {
                float t=Mathf.Clamp01(time/duration),ease=1-Mathf.Pow(1-t,3);
                card.anchoredPosition=Vector2.Lerp(begin,end,ease)+Vector2.up*(reducedMotion?0:Mathf.Sin(t*Mathf.PI)*95);
                card.localRotation=Quaternion.Slerp(rotation,Quaternion.Euler(0,0,angle),ease);
                if(reveal&&view!=null)
                {
                    view.ShowFace(reducedMotion||t>=.5f);
                    card.localScale=new Vector3(scale.x*(reducedMotion?1:Mathf.Max(.04f,Mathf.Abs(Mathf.Cos(t*Mathf.PI)))),scale.y,scale.z);
                }
                time+=Time.unscaledDeltaTime;yield return null;
            }
            card.anchoredPosition=end;card.localRotation=Quaternion.Euler(0,0,angle);card.localScale=scale;
            if(reveal&&view!=null)view.ShowFace(true);
        }
        void Effect(string text,Color color){StartCoroutine(Burst(text,color));}
        IEnumerator Burst(string text,Color color)
        {
            var label=Label(root,text,new Vector2(0,90),58,color);label.transform.SetAsLastSibling();
            float time=0;while(time<1){float t=time;label.color=new Color(color.r,color.g,color.b,1-t);label.rectTransform.localScale=Vector3.one*(reducedMotion?1:1+t*.3f);time+=Time.unscaledDeltaTime;yield return null;}Destroy(label.gameObject);
        }
        void Seat(string name,Vector2 at,string count,Color tint)
        {
            var p=Panel(root,name,at,new Vector2(170,100),Ink);
            Label(p,name,new Vector2(0,20),22,tint);Label(p,count+" CARDS",new Vector2(0,-17),16,Color.white);
        }
        RectTransform Card(RectTransform parent,CardState state,Vector2 at,bool faceUp=true)
        {
            var p=Panel(parent,state?.id??"draw deck",at,new Vector2(112,164),Color.white);
            var shadow=p.gameObject.AddComponent<Shadow>();shadow.effectColor=new Color(0,0,0,.45f);shadow.effectDistance=new Vector2(8,-12);
            var face=Panel(p,"Face",Vector2.zero,new Vector2(102,154),state==null?Ink:CardColor(state.color));face.GetComponent<Image>().raycastTarget=false;
            if(state!=null)
            {
                var art=new GameObject("Native card artwork",typeof(RectTransform),typeof(CanvasRenderer),typeof(UnoCardArtwork));
                var rect=art.GetComponent<RectTransform>();rect.SetParent(face,false);rect.anchorMin=Vector2.zero;rect.anchorMax=Vector2.one;rect.offsetMin=rect.offsetMax=Vector2.zero;
                art.GetComponent<UnoCardArtwork>().Configure(state);
            }
            var centerLabel=Label(face,state==null?"T":state.value=="skip"||state.value=="reverse"?"":state.Symbol,Vector2.zero,state==null?55:62,Color.white);
            var numberShadow=centerLabel.gameObject.AddComponent<Shadow>();numberShadow.effectColor=new Color(0,0,0,.45f);numberShadow.effectDistance=new Vector2(2,-3);
            Label(face,state?.Symbol??"TOMI",new Vector2(-28,57),16,state==null?Gold:Color.white);
            var bottom=Label(face,state?.Symbol??"PLAY",new Vector2(28,-57),16,Color.white);bottom.rectTransform.localEulerAngles=new Vector3(0,0,180);
            if(state!=null)
            {
                var back=Panel(p,"TOMI card back",Vector2.zero,new Vector2(102,154),Ink);
                Label(back,"T",Vector2.zero,55,Gold);Label(back,"TOMI PLAY",new Vector2(0,-45),11,Gold);
                back.GetComponent<Image>().raycastTarget=false;
                var view=p.gameObject.AddComponent<UnoCardReveal>();view.Front=face.gameObject;view.Back=back.gameObject;view.ShowFace(faceUp);
            }
            return p;
        }
        RectTransform Panel(RectTransform parent,string name,Vector2 at,Vector2 size,Color color)
        {
            var obj=new GameObject(name,typeof(RectTransform),typeof(CanvasRenderer),typeof(Image));var rect=obj.GetComponent<RectTransform>();rect.SetParent(parent,false);rect.sizeDelta=size;rect.anchoredPosition=at;
            var image=obj.GetComponent<Image>();image.sprite=rounded;image.type=Image.Type.Sliced;image.color=color;return rect;
        }
        Text Label(RectTransform parent,string text,Vector2 at,int size,Color color)
        {
            var obj=new GameObject(text,typeof(RectTransform),typeof(CanvasRenderer),typeof(Text));var label=obj.GetComponent<Text>();label.font=font;label.text=text;label.fontSize=size;label.alignment=TextAnchor.MiddleCenter;label.color=color;label.raycastTarget=false;
            var rect=obj.GetComponent<RectTransform>();rect.SetParent(parent,false);rect.sizeDelta=new Vector2(780,120);rect.anchoredPosition=at;return label;
        }
        void Button(RectTransform parent,string text,Vector2 at,Vector2 size,Color color,Action action)
        {
            var panel=Panel(parent,text,at,size,color);var button=panel.gameObject.AddComponent<Button>();button.onClick.AddListener(()=>action());
            var label=Label(panel,text,Vector2.zero,20,Ink);label.rectTransform.sizeDelta=size;
        }
        static Color CardColor(string color)
        {
            switch(color){case "red":return new Color(.89f,.19f,.29f);case "blue":return new Color(.15f,.4f,.96f);case "yellow":return new Color(.94f,.65f,.12f);case "green":return new Color(.04f,.6f,.43f);default:return new Color(.19f,.14f,.36f);}
        }
        void OnDestroy()
        {
            foreach(var material in sceneMaterials)if(material!=null)Destroy(material);
            if(rounded!=null){Destroy(rounded.texture);Destroy(rounded);}
            gate.Clear();pending=null;ActionRequested=null;
        }
        static Sprite RoundedSprite()
        {
            const int size=64,radius=14;var texture=new Texture2D(size,size,TextureFormat.RGBA32,false);
            for(int y=0;y<size;y++)for(int x=0;x<size;x++)
            {
                float dx=Mathf.Max(radius-x,x-(size-1-radius),0),dy=Mathf.Max(radius-y,y-(size-1-radius),0);
                texture.SetPixel(x,y,new Color(1,1,1,Mathf.Clamp01(radius-Mathf.Sqrt(dx*dx+dy*dy))));
            }
            texture.Apply();return Sprite.Create(texture,new Rect(0,0,size,size),new Vector2(.5f,.5f),100,0,SpriteMeshType.FullRect,new Vector4(radius,radius,radius,radius));
        }
    }
}
