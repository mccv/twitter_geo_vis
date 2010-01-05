import com.twitter.processing.*;
import processing.net.*;
import java.util.Set;

// global list of geos.  Max we display at a time.
// these get recycled if RECYCLE_TWEETS is true
GeoTweet []geos = new GeoTweet[10000];
// how many tweets are from a given source
HashMap sourceCounts = new HashMap();
// the color to use in the legend/dots for a source
HashMap sourceColors = new HashMap();

// whether to recycle tweets, or leave them on the map indefinitiely
boolean RECYCLE = true;
// our background image
PImage world;
// font to use for the legend title
PFont legendTitleFont;
// font to use for legend entries
PFont legendFont;
// 1080p-ish
int w = 1920;
int h = 1200;

// legend constraints
int maxBoxLen = 70;
int boxOffset = 15;
color legendColor = color(255);

// colors to cycle through for sources
color[] colors = new color[12];

// the next color to use from colors
int colorIdx = 0;

// total number of tweets we've seen
int tweetCount = 0;

// network client to use with streaming API
Client client;

// whether we've connected with our client
boolean connected = false;

void setup() {
  // init our color arrays for sources.  Should pick nicer ones...
  colors[0] = color(255, 0, 0);
  colors[1] = color(0, 255, 0);
  colors[2] = color(0, 0, 255);
  colors[3] = color(255, 255, 0);
  colors[4] = color(0, 255, 255);
  colors[5] = color(255, 0, 255);
  colors[6] = color(255, 128, 0);
  colors[7] = color(0, 255, 128);
  colors[8] = color(128, 0, 255);
  colors[9] = color(128, 128, 0);
  colors[10] = color(0, 128, 128);
  colors[11] = color(128, 0, 128);

  // load our background image
  world = loadImage("world.jpg");
  size(w, h);
  frameRate(30);
  smooth();
  
  // set up legend font stuff
  legendTitleFont = loadFont("AppleMyungjo-48.vlw");
  legendFont = loadFont("AppleMyungjo-24.vlw");

  // get our userid/password
  String [] lines = loadStrings("credentials.txt");
  if (lines.length == 2) {
    String user = lines[0];
    String password = lines[1];
    // open a geo hose connection, monitoring THE WORLD
    // IMPORTANT: in all likelihood you wont be able to monitor a bounding box of this size
    TweetStream stream = new TweetStream(this, "stream.twitter.com", 80, "1/statuses/filter.json?locations=-180,-90,180,90", user, password);
    stream.go();
  } else {
    println("couldn't load username/password from credentials.txt");
  }
}

void draw() {
  background(200);
  image(world, 0, 0, w, h);
  // draw our legend.  Do this first so tweets can overlay it if necessary
  legend();
  // look through each geo, calling update where appropriate
  for(int i = 0; i < geos.length; i++) {
    if (geos[i] != null) {
      if(geos[i].done) {
        geos[i] = null;
      } else {
        geos[i].update();
      }
    }
  }
}

void legend() {
  int startX = 100;
  int startY = 500;
  int stepY = 28;
  fill(legendColor);
  textFont(legendTitleFont, 48);
  // offset the legend a bit.
  text("Legend", startX - 10, startY - 10);
  textFont(legendFont, 24);
  
  // get all our sources as a sorted string array (painful)
  Object [] keyObj = sourceColors.keySet().toArray();
  String [] keys = new String[keyObj.length];
  for(int i = 0; i < keys.length; i++) {
    keys[i] = keyObj[i].toString();
  }
  keys = sort(keys);
  
  // find the maxcount to normalize legend box sizes
  int maxSrcTweets = 0;
  for(int i = 0; i < keys.length; i++) {
    String source = keys[i].toString();
    int numSrcTweets = int(sourceCounts.get(source).toString());
    if (numSrcTweets > maxSrcTweets ) maxSrcTweets = numSrcTweets;
  }

  // for each key, draw a legend entry
  ellipseMode(CORNER);
  for(int i = 0; i < keys.length; i++) {
    String source = keys[i].toString();
    int y = startY + (1+i)*stepY;
    int x = startX;
    fill(legendColor);
    text(source, x, y);
    
    // draw count box
    int numSrcTweets = int(sourceCounts.get(source).toString());
    int boxLen = int(maxBoxLen*(1.0*numSrcTweets)/maxSrcTweets);
    String cStr = sourceColors.get(source).toString();
    // drop shadow
    fill(128, 128, 128, 128);
    rect(x - boxLen - boxOffset +2, y - stepY/2 +2, boxLen  , stepY/2);
    arc(x - boxOffset - stepY/4 +1, y - stepY/2 +2, stepY/2, stepY/2, 0-PI/2, PI/2);
    // actual legend box
    fill(color(int(cStr)));
    rect(x - boxLen - boxOffset, y - stepY/2, boxLen  , stepY/2);
    arc(x - boxOffset - stepY/4 -1, y - stepY/2 , stepY/2, stepY/2, 0-PI/2, PI/2);
  }
  ellipseMode(CENTER);
}

// handle network events
void tweet(Status tweet) {
  Geo g = tweet.geo();
  // set up defaults for the source
  String src = "unknown";
  String srcLink = null;
  String srcStr = tweet.source();
  String [] srcMatches = match(srcStr, "href=\\\"(.*)\\\".*nofollow\\\">(.*)</a>");
  if(srcMatches != null) {
    src = srcMatches[2];
    srcLink = srcMatches[1];
  }
  if(g != null) {
    makeGeo(g.latitude(), g.longitude(), src, srcLink);
  }
}

// build a geo object from a lat/long, source, and source link
void makeGeo(double latitude, double longitude, String src, String srcLink) {
  // now create a new GeoTweet
  int idx = 0;
  while(idx < geos.length) {
    if(geos[idx] == null) {
      geos[idx] = new GeoTweet(latitude, longitude, src, srcLink);
      break;
    }
    idx += 1;
  }
  tweetCount += 1;
}

// convert a longitude to an x coordinate
float toXCoord(float f) {
  return (f+180) * w/360.0;
}

// convert a latitude to a y coordinate
float toYCoord(float f) {
  return ((-1.0*f)+90) * h/180.0;
}

class GeoTweet {
  float longitude, latitude;
  float x, y;
  float alpha = 0;
  String source = "unknown";
  String sourceLink = null;
  // whether we should be brightening the dot or not
  boolean up = true;
  // whether we're done rendering.  If RECYCLE is false we'll never hit this
  boolean done = false;
  // the number of circles to draw for each tweet.  We increase the size of each one slightly,
  // so more circles == bigger dots.
  int numCircles = 6;
  // the color components for the tweet
  float r, g, b, a;

  GeoTweet(double lat, double lon, String src, String srcLink) {
    longitude = new Float(lon).floatValue();
    latitude = new Float(lat).floatValue();
    source = src;
    sourceLink = srcLink;
    x = toXCoord(longitude);
    y = toYCoord(latitude);
    updateSourceCount();
    initSourceColor();
    //println("lat/long " + latitude + "/" + longitude + "=>" + x + "/" + y + ", source=" + source);
  }

  // find a source color for us
  void initSourceColor() {
    color c = color(255, 0, 0);
    if (sourceColors.get(source) == null) {
      c = colors[colorIdx];
      colorIdx += 1;
      colorIdx %= colors.length;
      sourceColors.put(source, int(c));
    } else {
      // hacky way to get colors stored in a map
      String cStr = sourceColors.get(source).toString();
      c = color(int(cStr));
    }
    r = red(c);
    g = green(c);
    b = blue(c);
    a = 0;
  }
  
  void updateSourceCount() {
    Object srcTweets = sourceCounts.get(source);
    int numSrcTweets = 0;
    // hacky way to get primitives stored in a map
    if (srcTweets != null) {
     numSrcTweets = int(srcTweets.toString());
    }
    sourceCounts.put(source, "" + (numSrcTweets +1));
  }

  void update() {
    // transparet stroke.  Should figure out how to just turn this off.
    stroke(255, 255, 255, 0);
    // draw gradually larger, gradually more transparent circles
    for(int i = 1; i < numCircles; i++) {
      fill(r, g, b, a*255/i);
      ellipse(x, y, sqrt(i*16), sqrt(i*16));
    }
    // if we're on the way up, increase alpha (brighten)
    if(up) {
      if(a < 1.0) {
        a += 0.25;
      }
    } else {
      // if we're on the way down, gradually fade out
      a -= 0.005;
    }
    // if we've peaked and RECYCLE is set to true, flip direction
    if (a >= 1.0 && RECYCLE) {
      up = false;
    } else if (a <= 0) {
      done = true;
    }
  }
}

