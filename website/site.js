// VJAG SITE ENGINE v0.99b
// writes the header, the navigation and the footer with document.write,
// exactly like the professionals did it in 1998.

var PAGES = [
  ["index.html", "MAIN", "HOME"],
  ["emulator.html", "EMU", "THE EMULATOR"],
  ["status.html", "STATUS", "DOES IT WORK?"],
  ["headless.html", "HEADLESS", "VJAG_TEST"],
  ["jagkit.html", "JAGKIT", "JAGKIT"],
  ["jaggame.html", "JAGGAME", "JAGGAME"],
  ["demos.html", "DEMOS", "GAMES + DEMOS"],
  ["video.html", "VIDEO", "MUSIC VIDEO"],
  ["tests.html", "TESTS", "317,500 TESTS"],
  ["download.html", "GET", "GET IT!!"],
  ["links.html", "LINKS", "COOL LINKS"],
  ["badges.html", "BADGES", "BADGE WALL"]
];

var REPO = "https://github.com/HelgeSverre/jaguar";

function begin(here) {
  var h = "";
  h += '<center>';
  h += '<table class="page" width="900" cellpadding="0" cellspacing="4">';
  h += '<tr><td colspan="2" align="center" style="background:#000;padding:10px 0 4px 0">';
  h += '<a href="index.html" style="text-decoration:none;background:none"><div class="logo">VJAG</div></a>';
  h += '<div class="pixel gold">AN ATARI JAGUAR EMULATOR WRITTEN IN <a class="vlink" href="https://docs.vlang.io/introduction.html">V</a></div>';
  h += '<img src="img/bar.gif" width="860" height="6" alt="" style="margin-top:8px">';
  h += '<marquee scrollamount="5" class="lime" style="margin:4px 0">';
  h += '*** WELCOME TO THE VJAG HOME PAGE *** 68000 + GPU + DSP + OBJECT PROCESSOR + BLITTER *** 317,500 OF 317,500 68000 TEST VECTORS PASS *** ';
  h += 'NO ROMS ON THIS SITE, BRING YOUR OWN *** WRITE JAGUAR GAMES IN V WITH JAGKIT AND JAGGAME *** THIS PAGE IS BEST VIEWED IN 326x240 ON A CRT *** GRAB A BADGE FROM THE BADGE WALL ***';
  h += '</marquee>';
  h += '</td></tr><tr>';
  h += '<td class="nav" width="170" align="center"><br>';
  h += '<div class="pixel red blink" style="margin-bottom:8px">&gt;&gt; NAVIGATE &lt;&lt;</div>';
  for (var i = 0; i < PAGES.length; i++) {
    var p = PAGES[i];
    var cls = p[1] === here ? "navbtn here" : "navbtn";
    h += '<a class="' + cls + '" href="' + p[0] + '">' + (p[1] === here ? "&#9658; " : "") + p[2] + '</a>';
  }
  h += '<br><img src="img/construction.gif" width="160" height="16" alt="UNDER CONSTRUCTION FOREVER"><br><br>';
  h += jukebox();
  h += '<br><div class="pixel gold">YOU ARE VISITOR</div><br>' + counter();
  h += '<div class="tiny grey" style="margin-top:4px">counted in your<br>browser only.</div><br>';
  h += '<a href="frames.html" class="small">[ FRAMES VERSION ]</a><br><br>';
  h += '<img class="btn88" src="img/btn/noroms.png" width="88" height="31" alt="NO ROMS"><br>';
  h += '<img class="btn88" src="img/btn/math.gif" width="88" height="31" alt="DO THE MATH"><br><br>';
  h += '</td><td class="content">';
  document.write(h);
}

function finish() {
  var h = "";
  h += '</td></tr><tr><td colspan="2" align="center" style="background:#000;padding:8px">';
  h += '<img src="img/bar.gif" width="860" height="6" alt=""><br><br>';
  h += buttonWall();
  h += '<p class="small">';
  for (var i = 0; i < PAGES.length; i++) {
    h += '[ <a href="' + PAGES[i][0] + '">' + PAGES[i][2].toLowerCase() + '</a> ] ';
  }
  h += '</p>';
  h += '<p class="small grey">vjag is MIT licensed. the source lives at <a href="' + REPO + '">' + REPO.replace("https://", "") + '</a>.<br>';
  h += 'No commercial ROMs or boot ROM images are hosted here or anywhere in the project. Atari and Jaguar are trademarks of their owners; this is a fan project and is not affiliated with them.<br>';
  h += 'Gameplay on this site is homebrew built in this repo and recorded by <code>vjag_test</code>.</p>';
  h += '<p class="small"><img src="img/mail.gif" width="32" height="24" alt="" style="vertical-align:middle"> ';
  h += 'Questions? Open an issue at <a href="' + REPO + '/issues">github.com/HelgeSverre/jaguar/issues</a> ';
  h += '<img src="img/mail.gif" width="32" height="24" alt="" style="vertical-align:middle"></p>';
  h += '<p class="tiny grey">This page was last updated: 13 November 2026 &middot; Made with Claude Code &middot; Netscape Now!</p>';
  h += '</td></tr></table></center>';
  document.write(h);
}

function buttonWall() {
  var b = ["v.png", "sdl.png", "m68k.png", "tom.png", "jerry.png", "term.gif", "just.png", "viewed.gif", "mac.png", "clawd.gif", "mit.png", "math.gif"];
  var h = "";
  for (var i = 0; i < b.length; i++) {
    h += '<img class="btn88" src="img/btn/' + b[i] + '" width="88" height="31" alt="">';
  }
  return h;
}

function counter() {
  var n = 1;
  try {
    n = parseInt(localStorage.getItem("vjag-hits") || "0", 10) + 1;
    localStorage.setItem("vjag-hits", String(n));
  } catch (e) {}
  var s = String(n);
  while (s.length < 7) s = "0" + s;
  var h = '<span class="odometer">';
  for (var i = 0; i < s.length; i++) h += "<span>" + s.charAt(i) + "</span>";
  return h + "</span>";
}

// the jukebox: background music, rendered by vjag's emulated DSP, never autoplayed
var TRACKS = [
  ["media/hero-bgm.mp3", "OMEGA OVERDRIVE", "Jaguar Hero, 180 BPM, played perfectly by the robot"],
  ["media/maw-bgm.mp3", "MAW", "150 BPM kick, rolling bass, acid line"],
  ["media/gg-bgm.mp3", "GHOSTGRID", "title screen theme"]
];
var bgm = null, bgmIndex = -1;

function jukebox() {
  var h = '<table cellpadding="3" cellspacing="0" style="border:3px ridge #808080;background:#000">';
  h += '<tr><td align="center" class="pixel gold">&#9835; JUKEBOX &#9835;</td></tr>';
  for (var i = 0; i < TRACKS.length; i++) {
    h += '<tr><td align="center"><button style="width:150px;font-size:10px" title="' + TRACKS[i][2] + '" onclick="playTrack(' + i + ')">&#9654; ' + TRACKS[i][1] + '</button></td></tr>';
  }
  h += '<tr><td align="center"><button style="width:150px;font-size:10px" onclick="stopTrack()">&#9632; STOP</button></td></tr>';
  h += '<tr><td align="center" class="tiny grey" id="nowplaying">rendered by the<br>emulated DSP</td></tr>';
  return h + "</table>";
}

// the player bar: one row fixed to the bottom of the screen while music is loaded
function playerBar() {
  var bar = document.getElementById("playerbar");
  if (bar) return bar;
  bar = document.createElement("div");
  bar.id = "playerbar";
  bar.hidden = true;
  // the console strip: fixed caps, stretchy plastic, the LCD stretches with the window
  bar.innerHTML =
    '<div class="pb-seg pb-a">' +
      '<button class="pb-btn" style="left:36.5%" id="pb-prev" title="previous track"><i>|&lt;</i></button>' +
      '<button class="pb-btn" style="left:49.1%" id="pb-play" title="play / pause"><i>||</i></button>' +
      '<button class="pb-btn" style="left:62.0%" id="pb-next" title="next track"><i>&gt;|</i></button>' +
      '<button class="pb-btn" style="left:74.9%" id="pb-mute" title="mute"><i>M</i></button>' +
      '<button class="pb-btn" style="left:87.7%" id="pb-stop" title="power off"><i>X</i></button>' +
    '</div>' +
    '<div class="pb-seg pb-b pb-stretch"></div>' +
    '<div class="pb-seg pb-c"><span class="pb-eye" style="left:27.5%"></span><span class="pb-eye" style="left:79.4%"></span></div>' +
    '<div class="pb-seg pb-d pb-stretch"></div>' +
    '<div class="pb-seg pb-e"></div>' +
    '<div class="pb-seg pb-f pb-stretch"><div class="pb-lcd">' +
      '<div class="pb-title"><span id="pb-name"></span></div>' +
      '<div class="pb-seek" id="pb-seek" title="seek"><div id="pb-fill"></div></div>' +
      '<div class="pb-time" id="pb-time">0:00/0:00</div>' +
    '</div></div>' +
    '<div class="pb-seg pb-g"></div>';
  document.body.appendChild(bar);
  var seek = document.getElementById("pb-seek");
  document.getElementById("pb-play").onclick = function () { if (!bgm) return; if (bgm.paused) bgm.play(); else bgm.pause(); };
  document.getElementById("pb-prev").onclick = function () { playTrack((bgmIndex + TRACKS.length - 1) % TRACKS.length); };
  document.getElementById("pb-next").onclick = function () { playTrack((bgmIndex + 1) % TRACKS.length); };
  document.getElementById("pb-mute").onclick = function () { if (bgm) { bgm.muted = !bgm.muted; this.classList.toggle("on", bgm.muted); } };
  document.getElementById("pb-stop").onclick = stopTrack;
  function seekTo(e) {
    if (!bgm || !bgm.duration) return;
    var r = seek.getBoundingClientRect(), f = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    bgm.currentTime = f * bgm.duration;
    bar._tick();
  }
  seek.addEventListener("pointerdown", function (e) {
    seekTo(e); seek.setPointerCapture(e.pointerId);
    seek.onpointermove = seekTo;
    seek.onpointerup = function () { seek.onpointermove = null; };
  });
  bar._tick = function () {
    if (!bgm) return;
    var d = bgm.duration || 0;
    document.getElementById("pb-fill").style.width = (d ? bgm.currentTime / d * 100 : 0) + "%";
    setTime(bgm.currentTime, d);
    document.getElementById("pb-play").innerHTML = bgm.paused ? "<i>&gt;</i>" : "<i>||</i>";
  };
  // the eyes flare with the sound, like the emulator's shell
  var eyes = bar.querySelectorAll(".pb-eye");
  bar._glow = function () {
    var lvl = 0;
    if (bar._analyser && bgm && !bgm.paused) {
      var buf = bar._buf; bar._analyser.getByteTimeDomainData(buf);
      for (var i = 0; i < buf.length; i++) { var v = Math.abs(buf[i] - 128); if (v > lvl) lvl = v; }
      lvl = Math.min(1, lvl / 90);
    } else if (bgm && !bgm.paused) {
      lvl = 0.35 + 0.35 * Math.abs(Math.sin(performance.now() / 333)); // a guess at the beat
    }
    for (var k = 0; k < eyes.length; k++) eyes[k].style.opacity = String(0.15 + lvl * 0.85);
    if (!bar.hidden) requestAnimationFrame(bar._glow);
  };
  return bar;
}

function hookEyes(bar, audio) {
  // opened as a local file, the browser hands Web Audio nothing but zeros and the
  // track goes silent, so the eyes only listen when the page comes over http(s)
  if (!/^https?:$/.test(location.protocol)) return;
  try {
    if (!bar._ctx) {
      bar._ctx = new (window.AudioContext || window.webkitAudioContext)();
      bar._analyser = bar._ctx.createAnalyser();
      bar._analyser.fftSize = 512;
      bar._buf = new Uint8Array(bar._analyser.fftSize);
      bar._analyser.connect(bar._ctx.destination);
    }
    bar._ctx.resume();
    bar._ctx.createMediaElementSource(audio).connect(bar._analyser);
  } catch (e) {}
}

function clock(sec) {
  sec = Math.floor(sec || 0);
  return Math.floor(sec / 60) + ":" + (sec % 60 < 10 ? "0" : "") + (sec % 60);
}
function setTime(cur, dur) { document.getElementById("pb-time").textContent = clock(cur) + "/" + clock(dur); }

function playTrack(i) {
  var bar = playerBar();
  if (bgm) { bgm.pause(); bgm = null; }
  bgm = new Audio(TRACKS[i][0]);
  bgm.loop = true;
  bgm.volume = 0.6;
  hookEyes(bar, bgm);
  ["timeupdate", "play", "pause", "loadedmetadata"].forEach(function (ev) { bgm.addEventListener(ev, bar._tick); });
  bgm.play();
  bgmIndex = i;
  document.getElementById("pb-name").textContent = "♫ " + TRACKS[i][1] + " *** " + TRACKS[i][2] + " *** rendered by the emulated DSP ♫";
  var wasHidden = bar.hidden;
  bar.hidden = false;
  document.body.classList.add("playing");
  if (wasHidden) requestAnimationFrame(bar._glow);
  var np = document.getElementById("nowplaying");
  if (np) np.innerHTML = '<span class="rainbow">NOW PLAYING</span><br>' + TRACKS[i][1];
}

function stopTrack() {
  if (bgm) { bgm.pause(); bgm = null; }
  var bar = document.getElementById("playerbar");
  if (bar) bar.hidden = true;
  document.body.classList.remove("playing");
  var np = document.getElementById("nowplaying");
  if (np) np.innerHTML = "rendered by the<br>emulated DSP";
}

// sparkle cursor trail. turn it off with the button on the badge wall.
(function () {
  var on = true;
  try { on = localStorage.getItem("vjag-sparkles") !== "off"; } catch (e) {}
  if (!on) return;
  var glyphs = ["*", "+", "✦", "✧", "·"];
  var colours = ["#ff2020", "#ffd700", "#ffffff", "#ff8000"];
  var last = 0;
  document.addEventListener("mousemove", function (e) {
    var now = Date.now();
    if (now - last < 40) return;
    last = now;
    var s = document.createElement("div");
    s.className = "sparkle";
    s.textContent = glyphs[Math.floor(Math.random() * glyphs.length)];
    s.style.color = colours[Math.floor(Math.random() * colours.length)];
    s.style.left = e.clientX + 6 + "px";
    s.style.top = e.clientY + 6 + "px";
    document.body.appendChild(s);
    var y = 0, life = 0;
    var t = setInterval(function () {
      y += 2; life++;
      s.style.transform = "translateY(" + y + "px)";
      s.style.opacity = String(1 - life / 20);
      if (life >= 20) { clearInterval(t); s.remove(); }
    }, 30);
  });
})();

function wavy(text) {
  var h = '<span class="wavy">';
  for (var i = 0; i < text.length; i++) {
    var c = text.charAt(i) === " " ? "&nbsp;" : text.charAt(i);
    h += '<span style="animation-delay:' + (i * 0.08).toFixed(2) + 's">' + c + "</span>";
  }
  document.write(h + "</span>");
}

function scrollTitle(text) {
  var t = text + "   ***   ";
  setInterval(function () {
    t = t.substring(1) + t.charAt(0);
    document.title = t;
  }, 200);
}

// THE EXPLODING V. hover any <a class="vlink"> and it blows up into the V logo.
var V_LOGO = '<svg viewBox="60 85 380 365" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">' +
  '<path d="M312 104 Q318 98 330 97 L418 94 Q430 94 426 106 L310 432 Q305 442 296 440 L250 300 Z" fill="#536b8a"/>' +
  '<path d="M84 94 L172 101 Q186 103 190 116 L305 432 Q308 442 296 442 L204 442 Q194 442 190 432 L72 108 Q70 94 84 94 Z" fill="#5d87bf"/>' +
  '</svg>';

function vBoom(a) {
  if (a._booming) return;
  a._booming = true;
  var r = a.getBoundingClientRect();
  var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
  a.classList.add("vshake");
  // debris: little Vs and sparks flying out
  var bits = ["V", "V", "V", "*", "✦", "+", "0.5.2", "fn", "mut", "V"];
  var colours = ["#5d87bf", "#536b8a", "#ffffff", "#ffd700", "#8fb4e8"];
  for (var i = 0; i < 28; i++) {
    var p = document.createElement("div");
    p.className = "vbit";
    p.textContent = bits[i % bits.length];
    p.style.color = colours[i % colours.length];
    p.style.left = cx + "px";
    p.style.top = cy + "px";
    p.style.fontSize = (10 + Math.random() * 18) + "px";
    document.body.appendChild(p);
    var ang = Math.random() * Math.PI * 2, dist = 80 + Math.random() * 180;
    var anim = p.animate([
      { transform: "translate(-50%,-50%) scale(0.2) rotate(0deg)", opacity: 1 },
      { transform: "translate(calc(-50% + " + Math.cos(ang) * dist + "px), calc(-50% + " + (Math.sin(ang) * dist + 60) + "px)) scale(1.4) rotate(" + (Math.random() * 720 - 360) + "deg)", opacity: 0 }
    ], { duration: 700 + Math.random() * 500, easing: "cubic-bezier(.1,.8,.3,1)" });
    anim.onfinish = (function (el) { return function () { el.remove(); }; })(p);
  }
  // the shockwave ring
  var ring = document.createElement("div");
  ring.className = "vring";
  ring.style.left = cx + "px";
  ring.style.top = cy + "px";
  document.body.appendChild(ring);
  ring.animate([{ transform: "translate(-50%,-50%) scale(0)", opacity: 1 }, { transform: "translate(-50%,-50%) scale(6)", opacity: 0 }], { duration: 600, easing: "ease-out" }).onfinish = function () { ring.remove(); };
  // the logo itself, out of the blast
  var logo = document.createElement("div");
  logo.className = "vlogo";
  logo.innerHTML = V_LOGO + '<div class="vcap">THE V PROGRAMMING LANGUAGE<br><span class="blink">CLICK TO LEARN V!!</span></div>';
  var lx = Math.min(Math.max(cx, 110), window.innerWidth - 110), ly = cy - 120 < 10 ? cy + 130 : cy - 110;
  logo.style.left = lx + "px";
  logo.style.top = ly + "px";
  document.body.appendChild(logo);
  logo.animate([
    { transform: "translate(-50%,-50%) scale(0) rotate(-540deg)", opacity: 0 },
    { transform: "translate(-50%,-50%) scale(1.35) rotate(15deg)", opacity: 1, offset: 0.7 },
    { transform: "translate(-50%,-50%) scale(1) rotate(0deg)", opacity: 1 }
  ], { duration: 650, easing: "ease-out", fill: "forwards" });
  a._vlogo = logo;
}

function vUnboom(a) {
  a.classList.remove("vshake");
  var logo = a._vlogo;
  a._vlogo = null;
  if (logo) {
    logo.animate([{ opacity: 1 }, { opacity: 0, transform: "translate(-50%,-50%) scale(0.3) rotate(180deg)" }], { duration: 250, fill: "forwards" }).onfinish = function () { logo.remove(); };
  }
  setTimeout(function () { a._booming = false; }, 300);
}

document.addEventListener("mouseover", function (e) {
  var a = e.target.closest && e.target.closest("a.vlink");
  if (a && !a.contains(e.relatedTarget)) vBoom(a);
});
document.addEventListener("mouseout", function (e) {
  var a = e.target.closest && e.target.closest("a.vlink");
  if (a && !a.contains(e.relatedTarget)) vUnboom(a);
});

var V_URL = "https://docs.vlang.io/introduction.html";
