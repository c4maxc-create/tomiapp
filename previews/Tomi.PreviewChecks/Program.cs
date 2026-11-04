using Tomi.BlazorPreview.Models;
static void Check(bool yes,string message){if(!yes)throw new Exception(message);}
int passed=0;
void Case(string name,Action action){action();passed++;Console.WriteLine("PASS "+name);}
Case("UNO rejects unowned and invalid wild plays, and preserves unique card identities",()=>{
 var m=new UnoModel();m.Reset();Check(m.Hand.Count==7&&m.Hand.Select(c=>c.Id).Distinct().Count()==7,"initial hand");
 Check(m.Play("foreign")==null,"foreign play");var wild=m.Hand.Single(c=>c.Color==null);Check(m.Play(wild.Id,"purple")==null&&m.Hand.Count==7,"invalid wild");
 Check(m.Play(wild.Id,"blue")!=null&&m.ActiveColor=="blue"&&m.Hand.Count==6,"valid wild");Check(m.Play(wild.Id,"red")==null,"repeat play");
 var old=m.Hand.Select(c=>c.Id).ToHashSet();m.Reset();Check(m.Hand.All(c=>!old.Contains(c.Id)),"fresh identities");for(int i=0;i<50;i++)m.Draw();Check(m.Hand.Count==12,"draw bound");
});
Case("Snakes serpentine geometry, jumps and exact finishing roll",()=>{
 Check(SnakeModel.Cell(1)==(5d,95d)&&SnakeModel.Cell(10)==(95d,95d)&&SnakeModel.Cell(11)==(95d,85d)&&SnakeModel.Cell(100)==(5d,5d),"serpentine");
 var m=new SnakeModel();m.Step();Check(m.Jump()==38,"ladder");m.Reset();for(int i=1;i<99;i++)m.Step();Check(!m.CanRoll(2)&&m.CanRoll(1)&&!m.CanRoll(0)&&!m.CanRoll(7),"exact roll");m.Step();Check(!m.CanRoll(1),"completed");
});
Case("Jackaroo wrap, backwards movement and local swapping",()=>{
 var m=new JackModel();m.Step(0,-4);Check(m.Positions[0]==60,"backwards");m.Step(0,13);Check(m.Positions[0]==9,"wrap");m.Selected=0;m.Swap();Check(m.Positions[0]==6&&m.Positions[1]==9,"swap");m.Reset();Check(m.Positions.SequenceEqual(new[]{0,6,15,23}),"reset");
});
Case("Camel covered/foreign/repeated tiles are rejected and undo conserves pieces",()=>{
 var m=new CamelModel();m.Reset();Check(m.Tiles.Count==54&&m.Tiles.Select(t=>t.Id).Distinct().Count()==54,"board identity");Check(m.Tiles.GroupBy(t=>t.Kind).All(g=>g.Count()==6),"triples distribution");
 var covered=m.Tiles.First(t=>!m.Free(t));Check(!m.Pick(covered.Id)&&!m.Pick(999),"illegal pick");var free=m.Tiles.First(m.Free);Check(m.Pick(free.Id)&&!m.Pick(free.Id),"ownership");Check(m.Undo()&&!m.Undo()&&m.Tiles.Count==54,"single undo");
});
Case("Camel side storage, shuffle conservation and capacity persist",()=>{
 var m=new CamelModel();m.Reset();var free=m.Tiles.First(m.Free);m.Pick(free.Id);Check(m.Store()&&!m.Store()&&m.Side.Count==1,"store");Check(m.Pick(free.Id,true)&&!m.Pick(free.Id,true),"return");
 var before=m.Tiles.Select(t=>t.Kind).Order().ToArray();Check(m.Shuffle()&&!m.Shuffle(),"shuffle count");Check(before.SequenceEqual(m.Tiles.Select(t=>t.Kind).Order()),"conservation");Check(m.Tiles.Count+m.Tray.Count+m.Side.Count+m.Matched==54,"total");
});
Case("Camel triples resolve before capacity loss and terminal games reject more actions",()=>{
 var m=new CamelModel();m.Reset();m.Tiles.Clear();m.Tray.Clear();m.Tiles.Add(new(900,0,0,0,8));m.Tray.AddRange(new[]{new Tile(901,0,0,0,8),new Tile(902,0,0,0,8),new Tile(903,0,0,0,1),new Tile(904,0,0,0,2),new Tile(905,0,0,0,3),new Tile(906,0,0,0,4)});
 Check(m.Pick(900)&&!m.Lost&&m.Tray.Count==4&&m.Matched==3,"triple before full");
 m.Reset();m.Tiles.Clear();m.Tray.Clear();m.Tiles.Add(new(900,0,0,0,8));for(int n=0;n<6;n++)m.Tray.Add(new(901+n,0,0,0,n));
 Check(m.Pick(900)&&m.Lost&&m.Tray.Count==7,"capacity loss");Check(!m.Undo()&&!m.Store()&&!m.Shuffle(),"terminal tools");
});
Case("Roulette CSS angle selects exactly the displayed segment on repeated spins",()=>{
 var m=new WheelModel();for(int round=0;round<3;round++)for(int i=0;i<8;i++){double before=m.Rotation;m.Spin(i);Check(m.Rotation-before>=1800&&m.Result==i,"spin progression");Check(Math.Abs((m.Rotation+22.5+45*i)%360)<.001,"pointer alignment");}
});
Console.WriteLine($"RESULT: {passed} passed, 0 failed");
