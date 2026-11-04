using UnityEngine;
using UnityEngine.UI;

namespace Tomi.Uno
{
    public sealed class PreviewBoardGraphic : MaskableGraphic
    {
        public enum Board { Snakes, Jackaroo, Wheel }
        public Board Kind;
        public static readonly Color[] Seats = { new Color(.95f,.3f,.4f), new Color(.2f,.6f,1), new Color(1,.78f,.25f), new Color(.2f,.8f,.5f) };
        public static Vector2 SnakeCell(int square)
        {
            int row=(square-1)/10, col=(square-1)%10;
            if(row%2!=0)col=9-col;
            return new Vector2((col+.5f)/10,(row+.5f)/10);
        }
        public static Vector2 JackCell(int seat,int position)
        {
            if(position<0)return new Vector2(.5f,.5f);
            float a=Mathf.PI*.5f+seat*Mathf.PI*.5f;
            if(position>=64)return Vector2.one*.5f+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*(.13f+(position-64)*.045f);
            a=Mathf.PI*.5f+((position+seat*16)%64)*Mathf.PI/32;
            return Vector2.one*.5f+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*(.355f+.035f*Mathf.Cos(a*4));
        }
        protected override void OnPopulateMesh(VertexHelper h)
        {
            h.Clear();raycastTarget=false;
            var r=rectTransform.rect;var center=r.center;
            if(Kind==Board.Snakes)
            {
                for(int n=1;n<=100;n++)
                {
                    var p=SnakeCell(n);var c=r.min+Vector2.Scale(p,r.size);var half=r.size/20;
                    Quad(h,c-half,c+new Vector2(half.x,-half.y),c+half,c+new Vector2(-half.x,half.y),n%2==0?new Color(.17f,.35f,.32f):new Color(.25f,.46f,.38f));
                }
                Link(h,r,2,38,new Color(1,.8f,.3f));Link(h,r,28,84,new Color(1,.8f,.3f));
                Link(h,r,16,6,new Color(.95f,.35f,.45f));Link(h,r,99,80,new Color(.95f,.35f,.45f));
            }
            else if(Kind==Board.Jackaroo)
            {
                Disc(h,center,r.width*.48f,new Color(.8f,.6f,.32f));
                Disc(h,center,r.width*.46f,new Color(.94f,.81f,.57f));
                for(int i=0;i<64;i++)Disc(h,r.min+Vector2.Scale(JackCell(0,i),r.size),r.width*.011f,i%16==0?Seats[i/16]:new Color(.43f,.3f,.18f));
                for(int seat=0;seat<4;seat++)for(int i=0;i<4;i++)Disc(h,r.min+Vector2.Scale(JackCell(seat,64+i),r.size),r.width*.013f,Seats[seat]);
            }
            else
            {
                var colors=new[]{new Color(.94f,.3f,.35f),new Color(1,.69f,.22f),new Color(.22f,.71f,.47f),new Color(.25f,.55f,.95f)};
                float radius=r.width*.47f;
                Disc(h,center,radius+8,new Color(1,.82f,.42f));
                for(int i=0;i<8;i++)for(int j=0;j<8;j++)
                {
                    float a=(90-i*45-22.5f+j*45f/8)*Mathf.Deg2Rad,b=(90-i*45-22.5f+(j+1)*45f/8)*Mathf.Deg2Rad;
                    Triangle(h,center,center+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*radius,center+new Vector2(Mathf.Cos(b),Mathf.Sin(b))*radius,colors[i%4]);
                }
                Disc(h,center,radius*.16f,new Color(.06f,.16f,.2f));
            }
        }
        static void Link(VertexHelper h,Rect r,int from,int to,Color tint)
        {
            var a=r.min+Vector2.Scale(SnakeCell(from),r.size);var b=r.min+Vector2.Scale(SnakeCell(to),r.size);
            var d=(b-a).normalized;var n=new Vector2(-d.y,d.x)*r.width*.009f;
            Quad(h,a-n,b-n,b+n,a+n,tint);
        }
        static void Quad(VertexHelper h,Vector2 a,Vector2 b,Vector2 c,Vector2 d,Color tint)
        {
            int n=h.currentVertCount;h.AddVert(a,tint,Vector2.zero);h.AddVert(b,tint,Vector2.zero);h.AddVert(c,tint,Vector2.zero);h.AddVert(d,tint,Vector2.zero);h.AddTriangle(n,n+1,n+2);h.AddTriangle(n,n+2,n+3);
        }
        static void Triangle(VertexHelper h,Vector2 a,Vector2 b,Vector2 c,Color tint)
        {
            int n=h.currentVertCount;h.AddVert(a,tint,Vector2.zero);h.AddVert(b,tint,Vector2.zero);h.AddVert(c,tint,Vector2.zero);h.AddTriangle(n,n+1,n+2);
        }
        static void Disc(VertexHelper h,Vector2 c,float radius,Color tint)
        {
            for(int i=0;i<48;i++)Triangle(h,c,c+new Vector2(Mathf.Cos(i*Mathf.PI/24),Mathf.Sin(i*Mathf.PI/24))*radius,c+new Vector2(Mathf.Cos((i+1)*Mathf.PI/24),Mathf.Sin((i+1)*Mathf.PI/24))*radius,tint);
        }
    }
}
