using UnityEngine;
using UnityEngine.UI;

namespace Tomi.Uno
{
    // Native Unity UI geometry. No browser, textures, imported card art or extra packages.
    public sealed class UnoCardArtwork : MaskableGraphic
    {
        string symbol;
        bool wild;
        public void Configure(CardState card)
        {
            symbol = card.value;
            wild = card.color == null;
            raycastTarget = false;
            SetVerticesDirty();
        }
        protected override void OnPopulateMesh(VertexHelper mesh)
        {
            mesh.Clear();
            var size = rectTransform.rect.size;
            var center = rectTransform.rect.center;
            // A tilted ivory orbit gives the cards depth without copying UNO assets.
            var axes = new Vector2(size.x * .37f, size.y * .34f);
            const int segments = 64;
            for (int i = 0; i < segments; i++)
            {
                float a = i * Mathf.PI * 2 / segments, b = (i + 1) * Mathf.PI * 2 / segments;
                Quad(mesh, center + Ellipse(a, axes), center + Ellipse(b, axes),
                    center + Ellipse(b, axes * .91f), center + Ellipse(a, axes * .91f), new Color(1, .98f, .9f, .93f));
            }
            if (wild)
            {
                var colors = new[] {new Color(.95f,.24f,.32f), new Color(.25f,.52f,1), new Color(.2f,.75f,.43f), new Color(1,.77f,.2f)};
                for (int i = 0; i < 4; i++)
                    Disc(mesh, center + new Vector2((i % 2 == 0 ? -1 : 1) * 17, (i < 2 ? 1 : -1) * 17), 22, colors[i]);
            }
            if (symbol == "skip")
            {
                Ring(mesh, center, 23, 6, Color.white);
                Strip(mesh, center + new Vector2(-18,-18), center + new Vector2(18,18), 6, Color.white);
            }
            else if (symbol == "reverse")
            {
                Arrow(mesh, center, 23, 20, 140);
                Arrow(mesh, center, 23, 200, 140);
            }
        }
        static Vector2 Ellipse(float angle, Vector2 axes)
        {
            var p = new Vector2(Mathf.Cos(angle) * axes.x, Mathf.Sin(angle) * axes.y);
            const float tilt = -.28f;
            return new Vector2(p.x * Mathf.Cos(tilt) - p.y * Mathf.Sin(tilt), p.x * Mathf.Sin(tilt) + p.y * Mathf.Cos(tilt));
        }
        static void Quad(VertexHelper mesh, Vector2 a, Vector2 b, Vector2 c, Vector2 d, Color tint)
        {
            int n = mesh.currentVertCount;
            mesh.AddVert(a, tint, Vector2.zero); mesh.AddVert(b, tint, Vector2.zero);
            mesh.AddVert(c, tint, Vector2.zero); mesh.AddVert(d, tint, Vector2.zero);
            mesh.AddTriangle(n, n+1, n+2); mesh.AddTriangle(n, n+2, n+3);
        }
        static void Strip(VertexHelper mesh, Vector2 a, Vector2 b, float width, Color tint)
        {
            var along = (b-a).normalized;
            var side = new Vector2(-along.y, along.x) * width * .5f;
            Quad(mesh, a-side, b-side, b+side, a+side, tint);
        }
        static void Ring(VertexHelper mesh, Vector2 center, float radius, float width, Color tint)
        {
            for (int i=0;i<48;i++)
            {
                float a=i*Mathf.PI*2/48, b=(i+1)*Mathf.PI*2/48;
                Strip(mesh, center+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*radius,
                    center+new Vector2(Mathf.Cos(b),Mathf.Sin(b))*radius, width, tint);
            }
        }
        static void Disc(VertexHelper mesh, Vector2 center, float radius, Color tint)
        {
            for(int i=0;i<32;i++)
            {
                float a=i*Mathf.PI*2/32,b=(i+1)*Mathf.PI*2/32;
                int n=mesh.currentVertCount;
                mesh.AddVert(center,tint,Vector2.zero);
                mesh.AddVert(center+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*radius,tint,Vector2.zero);
                mesh.AddVert(center+new Vector2(Mathf.Cos(b),Mathf.Sin(b))*radius,tint,Vector2.zero);
                mesh.AddTriangle(n,n+1,n+2);
            }
        }
        static void Arrow(VertexHelper mesh,Vector2 center,float radius,float start,float sweep)
        {
            Vector2 last=Vector2.zero;
            for(int i=0;i<24;i++)
            {
                float a=(start+sweep*i/24)*Mathf.Deg2Rad,b=(start+sweep*(i+1)/24)*Mathf.Deg2Rad;
                var from=center+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*radius;
                last=center+new Vector2(Mathf.Cos(b),Mathf.Sin(b))*radius;
                Strip(mesh,from,last,6,Color.white);
            }
            float end=(start+sweep)*Mathf.Deg2Rad;
            var tangent=new Vector2(-Mathf.Sin(end),Mathf.Cos(end));
            var normal=new Vector2(-tangent.y,tangent.x);
            int n=mesh.currentVertCount;
            mesh.AddVert(last+tangent*7,Color.white,Vector2.zero);
            mesh.AddVert(last-tangent*6+normal*9,Color.white,Vector2.zero);
            mesh.AddVert(last-tangent*6-normal*9,Color.white,Vector2.zero);
            mesh.AddTriangle(n,n+1,n+2);
        }
    }

}
