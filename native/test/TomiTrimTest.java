import com.example.video_compress.TomiTrim;
public final class TomiTrimTest {
  static void check(long total, int start, Integer duration, long wantStart, long wantEnd) {
    long[] result = TomiTrim.bounds(total,start,duration);
    if(result[0]!=wantStart || result[1]!=wantEnd) throw new AssertionError("Incorrect selected interval");
    if(total*1000L-result[0]-result[1]<=0) throw new AssertionError("Empty selected clip");
  }
  public static void main(String[] args) {
    check(17374,0,18,0,0); // Whole short clip used to discard its entire duration.
    check(17374,0,17,0,374000);
    check(17374,5,10,5000000,2374000);
    check(300000,0,180,0,120000000);
    check(300900,120,180,120000000,900000);
    check(3600000,2400,180,2400000000L,1020000000L); // Beyond 32-bit micros.
    check(17374,3,null,3000000,0);
    for(int[] bad:new int[][]{{0,0,1},{1000,-1,1},{1000,1,1},{1000,0,0}}) {
      try {TomiTrim.bounds(bad[0],bad[1],bad[2]);throw new AssertionError("Invalid interval accepted");}
      catch(IllegalArgumentException expected) {}
    }
    System.out.println("PASS: 11 native trim intervals, including full clips and long-source offsets.");
  }
}
