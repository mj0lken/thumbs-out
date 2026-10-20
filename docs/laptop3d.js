// The intro's MacBook Pro 14" in WebGL. site.js drives it with two numbers: how far the lid is
// open and how far the camera has zoomed into the screen (both 0–1).
import * as THREE from "./vendor/three/three.module.min.js";
import { RoomEnvironment } from "./vendor/three/RoomEnvironment.js";

// Real dimensions, in centimetres.
const W = 31.26;
const D = 22.12;
const BASE_T = 1.1;
const LID_T = 0.45;
const CORNER = 1.25;
const OPEN_ANGLE = THREE.MathUtils.degToRad(108);
const DISPLAY = { side: 0.55, top: 0.55, chin: 1.95 }; // bezels around the display, on the lid
const DISPLAY_W = W - 2 * DISPLAY.side;
const DISPLAY_D = D - DISPLAY.top - DISPLAY.chin;
const FOV = 28;
const LAPTOP_RADIUS = 30; // contains the open laptop around any camera target

// The outlined thumbs-up (same paths as the site's SVG and ThumbMark.swift, 24-unit grid).
const CUFF = "M3.2 10.2h1.6a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H3.2a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1z";
const HAND = "M7.4 21.2V11.2L11 3.6C11.6 2.4 13.5 2.7 13.5 4.2L13 9.6H19C20.3 9.6 21.3 10.9 20.9 12.2L19 19.5C18.7 20.6 17.8 21.2 16.8 21.2Z";

export function createLaptopView(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  try {
    return setUpView(renderer);
  } catch (error) {
    // Don't leave a WebGL context behind when the scene can't be built (e.g. no canvas roundRect).
    dispose(renderer);
    throw error;
  }
}

function dispose(renderer) {
  renderer.dispose();
  renderer.forceContextLoss();
}

function setUpView(renderer) {
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  const key = new THREE.DirectionalLight(0xffffff, 1.2);
  key.position.set(-20, 40, 30);
  scene.add(key);

  const camera = new THREE.PerspectiveCamera(FOV, 1, 4, 400);
  const laptop = buildLaptop(renderer, scene.environment);
  scene.add(laptop.group);

  let layout = null;
  let drawn = null; // what's on the canvas: skip renders that wouldn't change it

  /** Viewport size and where the closed laptop should sit (below the headline). */
  function resize({ width, height, copyBottom }) {
    // Read on every resize: browser zoom and moving between displays change it.
    const pixelRatio = Math.min(window.devicePixelRatio, 2);
    const size = renderer.getSize(new THREE.Vector2());
    if (renderer.getPixelRatio() !== pixelRatio || size.x !== width || size.y !== height) {
      renderer.setPixelRatio(pixelRatio);
      renderer.setSize(width, height, false);
    }
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    layout = computeLayout(width, height, copyBottom);
    drawn = null;
  }

  /** open, zoom: 0–1, already eased by the caller. */
  function update({ open, zoom }) {
    if (!layout || (drawn && drawn.open === open && drawn.zoom === zoom)) return;
    drawn = { open, zoom };
    laptop.pivot.rotation.x = -OPEN_ANGLE * open;
    laptop.updateFaces(open);

    const closed = layout.closed;
    const opened = layout.opened;
    const target = new THREE.Vector3().lerpVectors(closed.target, opened.target, open);
    const position = new THREE.Vector3().lerpVectors(closed.position, opened.position, open);
    if (zoom > 0) {
      const screen = displayPose(laptop);
      position.lerp(screen.position, zoom);
      target.lerp(screen.target, zoom);
    }
    camera.position.copy(position);
    camera.lookAt(target);
    // Clip tightly around the laptop: depth precision for the thin layers on the lid and deck
    // (some GPUs give a 16-bit depth buffer, and phones view the laptop from far away).
    const distance = position.distanceTo(target);
    camera.near = Math.max(1, distance - LAPTOP_RADIUS);
    camera.far = distance + LAPTOP_RADIUS;
    camera.updateProjectionMatrix();
    renderer.render(scene, camera);
  }

  function computeLayout(width, height, copyBottom) {
    const tanHalf = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
    const aspect = width / height;

    // Closed: seen from above at 40°, sized to fit between the headline and the bottom edge.
    const available = Math.max(height - copyBottom - 24, height * 0.28);
    const closedWidthPx = Math.min(width * (width < 760 ? 0.86 : 0.46), available / 0.62, 640);
    const closedDistance = (W / closedWidthPx) * (width / (2 * tanHalf * aspect));
    const closedCenter = new THREE.Vector3(0, BASE_T, 0);
    const elevation = 0.6; // ~34°: enough to see the lid, still showing the front edge
    const closedDirection = new THREE.Vector3(0, Math.sin(elevation), Math.cos(elevation));
    // Aim above the laptop so it lands lower on screen, centred in the space below the copy.
    const wantY = copyBottom + available / 2 + 8;
    const shift = ((wantY - height / 2) / height) * 2 * closedDistance * tanHalf;
    const closedUp = new THREE.Vector3(0, Math.cos(elevation), -Math.sin(elevation));
    const closed = {
      position: closedCenter.clone().addScaledVector(closedDirection, closedDistance).addScaledVector(closedUp, shift),
      target: closedCenter.clone().addScaledVector(closedUp, shift),
    };

    // Open: a little above eye level, the whole laptop filling most of the view.
    const openCenter = new THREE.Vector3(0, 10, -4);
    const openHeight = 30; // base plus open lid, in cm
    const openDistance = Math.max(openHeight / (2 * tanHalf * 0.78), W / (2 * tanHalf * aspect * 0.8));
    const openDirection = new THREE.Vector3(0, Math.sin(0.2), Math.cos(0.2));
    const opened = { position: openCenter.clone().addScaledVector(openDirection, openDistance), target: openCenter };

    return { closed, opened, tanHalf, aspect };
  }

  /** Camera pose that puts the display square-on and just covering the viewport. */
  function displayPose(view) {
    view.group.updateMatrixWorld(true);
    const center = view.displayCenter.clone().applyMatrix4(view.pivot.matrixWorld);
    const normal = new THREE.Vector3(0, -1, 0).transformDirection(view.pivot.matrixWorld);
    const { tanHalf, aspect } = layout;
    const distance = Math.min(DISPLAY_D / (2 * tanHalf), DISPLAY_W / (2 * tanHalf * aspect)) * 0.97;
    return { position: center.clone().addScaledVector(normal, distance), target: center };
  }

  return { resize, update, dispose: () => dispose(renderer) };
}

// ---------- Model ----------

function buildLaptop(renderer, environment) {
  const group = new THREE.Group();
  const aluminium = new THREE.MeshPhysicalMaterial({ color: 0xc9ccd1, metalness: 1, roughness: 0.36 });
  const anisotropy = renderer.capabilities.getMaxAnisotropy();

  const base = new THREE.Mesh(slab(W, D, BASE_T, CORNER, 0.22), aluminium);
  group.add(base);

  // Keyboard, speakers and trackpad, drawn onto the deck.
  const deck = new THREE.Mesh(
    new THREE.PlaneGeometry(W - 0.6, D - 0.6).rotateX(-Math.PI / 2),
    overlay(new THREE.MeshStandardMaterial({ map: canvasTexture(drawDeck, 2048, Math.round(2048 * (D - 0.6) / (W - 0.6)), anisotropy), transparent: true, roughness: 0.55, metalness: 0.3 })),
  );
  deck.position.y = BASE_T + 0.02;
  group.add(deck);

  // The lid hinges at the back edge of the base.
  const pivot = new THREE.Group();
  pivot.position.set(0, BASE_T + 0.02, -D / 2);
  group.add(pivot);

  const lid = new THREE.Mesh(slab(W, D, LID_T, CORNER, 0.12), aluminium);
  lid.position.z = D / 2;
  pivot.add(lid);

  // Black glass over the lid's inside face, then the display on top of it.
  const glass = new THREE.Mesh(
    new THREE.ShapeGeometry(roundedRect(W - 0.16, D - 0.16, CORNER - 0.08), 12).rotateX(Math.PI / 2),
    // Its own, dimmed copy of the environment: the room's light panels would otherwise mirror
    // in it and turn the bezel grey.
    overlay(new THREE.MeshPhysicalMaterial({ color: 0x050506, roughness: 0.2, metalness: 0, clearcoat: 0.4, clearcoatRoughness: 0.2, envMap: environment, envMapIntensity: 0.07 }), 1),
  );
  glass.position.set(0, -0.015, D / 2);
  pivot.add(glass);

  const displayCenter = new THREE.Vector3(0, -0.04, DISPLAY.chin + DISPLAY_D / 2);
  const display = new THREE.Mesh(
    displayGeometry(),
    overlay(new THREE.MeshBasicMaterial({ map: canvasTexture(drawScreen, 2048, Math.round(2048 * DISPLAY_D / DISPLAY_W), anisotropy), toneMapped: false })),
  );
  display.position.copy(displayCenter);
  pivot.add(display);

  // A thumbs-out sticker on the lid, a little askew.
  const sticker = new THREE.Mesh(
    new THREE.PlaneGeometry(5.4, 5.4).rotateX(-Math.PI / 2).rotateY(THREE.MathUtils.degToRad(9)),
    overlay(new THREE.MeshStandardMaterial({ map: canvasTexture(drawSticker, 512, 512, anisotropy), transparent: true, roughness: 0.4 })),
  );
  sticker.position.set(6.6, LID_T + 0.03, D * 0.38);
  pivot.add(sticker);

  // A soft contact shadow under the base.
  const shadow = new THREE.Mesh(
    new THREE.PlaneGeometry(W * 1.5, D * 1.6).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map: canvasTexture(drawShadow, 256, 256), transparent: true, depthWrite: false, toneMapped: false }),
  );
  shadow.position.y = -0.02;
  group.add(shadow);

  return {
    group, pivot, displayCenter,
    updateFaces(open) {
      // The display lights up as the lid opens.
      display.material.color.setScalar(THREE.MathUtils.clamp(open * 1.6, 0, 1));
    },
  };
}

/** Thin layers drawn on top of a surface: pulled forward in depth so they never flicker.
 *  A higher level wins over a lower one (the display over the glass under it). */
function overlay(material, level = 2) {
  material.polygonOffset = true;
  material.polygonOffsetFactor = -level;
  material.polygonOffsetUnits = -4 * level;
  return material;
}

/** The display panel: top corners concentric with the lid's, softer ones at the bottom. */
function displayGeometry() {
  const geometry = new THREE.ShapeGeometry(roundedRect(DISPLAY_W, DISPLAY_D, CORNER - DISPLAY.side, 0.3), 12);
  // ShapeGeometry's UVs are in shape units; map them onto the screen texture's 0–1 range.
  const uv = geometry.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / DISPLAY_W + 0.5, uv.getY(i) / DISPLAY_D + 0.5);
  return geometry.rotateX(Math.PI / 2);
}

/** A slab with rounded corners in plan and softened edges, lying on y = 0. */
function slab(width, depth, thickness, radius, bevel) {
  const geometry = new THREE.ExtrudeGeometry(roundedRect(width - 2 * bevel, depth - 2 * bevel, radius - bevel), {
    depth: thickness - 2 * bevel, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel,
    bevelSegments: 5, curveSegments: 24,
  });
  geometry.rotateX(-Math.PI / 2);
  geometry.translate(0, bevel, 0);
  geometry.computeVertexNormals();
  return geometry;
}

/** `radius` rounds the corners at +depth (the top of the screen), `bottomRadius` those at -depth. */
function roundedRect(width, depth, radius, bottomRadius = radius) {
  const x = -width / 2;
  const y = -depth / 2;
  const shape = new THREE.Shape();
  shape.moveTo(x + bottomRadius, y);
  shape.lineTo(x + width - bottomRadius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + bottomRadius);
  shape.lineTo(x + width, y + depth - radius);
  shape.quadraticCurveTo(x + width, y + depth, x + width - radius, y + depth);
  shape.lineTo(x + radius, y + depth);
  shape.quadraticCurveTo(x, y + depth, x, y + depth - radius);
  shape.lineTo(x, y + bottomRadius);
  shape.quadraticCurveTo(x, y, x + bottomRadius, y);
  return shape;
}

// ---------- Textures ----------

function canvasTexture(draw, width, height, anisotropy = 1) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  draw(canvas.getContext("2d"), width, height);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = anisotropy;
  return texture;
}

function roundRect(ctx, x, y, width, height, radius) {
  ctx.beginPath();
  ctx.roundRect(x, y, width, height, radius);
}

/** The desktop: same wallpaper, menu bar and notch as the HTML stage that takes over. */
function drawScreen(ctx, width, height) {
  const wallpaper = ctx.createRadialGradient(width * 0.7, 0, 0, width * 0.7, 0, width * 0.9);
  wallpaper.addColorStop(0, "#2B2A5C");
  wallpaper.addColorStop(0.55, "#15142B");
  wallpaper.addColorStop(1, "#15142B");
  ctx.fillStyle = wallpaper;
  ctx.fillRect(0, 0, width, height);

  const bar = height * 0.036;
  ctx.fillStyle = "rgba(255,255,255,0.1)";
  ctx.fillRect(0, 0, width, bar);
  ctx.fillStyle = "rgba(255,255,255,0.92)";
  ctx.font = `600 ${bar * 0.5}px -apple-system, system-ui, sans-serif`;
  ctx.textBaseline = "middle";
  ctx.beginPath();
  ctx.ellipse(width * 0.02, bar / 2, bar * 0.2, bar * 0.24, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillText("Cursor", width * 0.035, bar / 2);
  ctx.font = `400 ${bar * 0.5}px -apple-system, system-ui, sans-serif`;
  ["File", "Edit", "View", "Window"].forEach((label, index) => ctx.fillText(label, width * (0.085 + index * 0.035), bar / 2));
  ctx.fillText("Tue 15:42", width * 0.93, bar / 2);

  // The thumb in the menu bar.
  ctx.save();
  ctx.translate(width * 0.885, bar * 0.14);
  const scale = (bar * 0.72) / 21;
  ctx.scale(scale, scale);
  ctx.translate(-1, -1.4);
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  ctx.stroke(new Path2D(CUFF));
  ctx.stroke(new Path2D(HAND));
  ctx.restore();

  // The camera notch.
  ctx.fillStyle = "#000";
  roundRect(ctx, width * 0.4525, -bar, width * 0.095, bar * 2, bar * 0.45);
  ctx.fill();
}

/** Keyboard (MacBook Pro layout), speaker grilles, hinge shadow and trackpad, on transparency. */
function drawDeck(ctx, width, height) {
  const u = width / 30.66; // pixels per centimetre
  ctx.fillStyle = "rgba(20,20,22,0.55)";
  roundRect(ctx, 3.2 * u, 0, width - 6.4 * u, 0.55 * u, 0.3 * u);
  ctx.fill();

  // Speaker grilles.
  ctx.fillStyle = "rgba(30,30,34,0.85)";
  for (const left of [0.75, width / u - 2.85]) {
    for (let y = 1.2; y < 11.4; y += 0.32) {
      for (let x = left; x < left + 2.1; x += 0.32) {
        ctx.beginPath();
        ctx.arc(x * u, y * u, 0.07 * u, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  // Keyboard well and keys (each row adds up to 14.5 key widths).
  const kx = 3.25 * u;
  const ky = 1.1 * u;
  const kw = width - 6.5 * u;
  const kh = 10.3 * u;
  ctx.fillStyle = "rgba(26,26,29,0.9)";
  roundRect(ctx, kx, ky, kw, kh, 0.35 * u);
  ctx.fill();
  const rows = [
    [1.5, ...Array(12).fill(1), 1],
    [...Array(13).fill(1), 1.5],
    [1.5, ...Array(13).fill(1)],
    [1.8, ...Array(11).fill(1), 1.7],
    [2.3, ...Array(10).fill(1), 2.2],
    [1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1],
  ];
  const gap = 0.16 * u;
  const pad = 0.18 * u;
  const unit = (kw - 2 * pad) / 14.5;
  const heights = [0.62, 1, 1, 1, 1, 1];
  const rowUnit = (kh - 2 * pad - gap * 5) / heights.reduce((a, b) => a + b, 0);
  let y = ky + pad;
  rows.forEach((row, rowIndex) => {
    let x = kx + pad;
    const rowHeight = rowUnit * heights[rowIndex];
    row.forEach((keyWidth, index) => {
      const w = keyWidth * unit - gap;
      const gradient = ctx.createLinearGradient(0, y, 0, y + rowHeight);
      gradient.addColorStop(0, "#121214");
      gradient.addColorStop(1, "#08080A");
      ctx.fillStyle = gradient;
      roundRect(ctx, x, y, w, rowHeight, 0.12 * u);
      ctx.fill();
      if (rowIndex === 0 && index === row.length - 1) {
        ctx.strokeStyle = "rgba(255,255,255,0.12)";
        ctx.lineWidth = 0.04 * u;
        ctx.beginPath();
        ctx.arc(x + w / 2, y + rowHeight / 2, rowHeight * 0.32, 0, Math.PI * 2);
        ctx.stroke();
      }
      x += keyWidth * unit;
    });
    y += rowHeight + gap;
  });

  // Trackpad: a faint recess in the aluminium.
  const tw = 15.2 * u;
  const th = 9.4 * u;
  const tx = (width - tw) / 2;
  const ty = height - th - 0.9 * u;
  ctx.fillStyle = "rgba(0,0,0,0.05)";
  roundRect(ctx, tx, ty, tw, th, 0.6 * u);
  ctx.fill();
  ctx.strokeStyle = "rgba(0,0,0,0.22)";
  ctx.lineWidth = 0.035 * u;
  ctx.stroke();
}

function drawSticker(ctx, width) {
  const s = width;
  ctx.fillStyle = "#fff";
  roundRect(ctx, s * 0.02, s * 0.02, s * 0.96, s * 0.96, s * 0.25);
  ctx.fill();
  ctx.fillStyle = "#15142B";
  roundRect(ctx, s * 0.08, s * 0.08, s * 0.84, s * 0.84, s * 0.2);
  ctx.fill();
  ctx.save();
  const scale = (s * 0.84 * 0.56) / 18.8;
  ctx.translate(s / 2 - 11.55 * scale, s / 2 - 11.8 * scale);
  ctx.scale(scale, scale);
  ctx.strokeStyle = "#34E07F";
  ctx.lineWidth = 1.75;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.stroke(new Path2D(CUFF));
  ctx.stroke(new Path2D(HAND));
  ctx.restore();
}

function drawShadow(ctx, width, height) {
  const gradient = ctx.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, width / 2);
  gradient.addColorStop(0, "rgba(21,20,43,0.32)");
  gradient.addColorStop(0.55, "rgba(21,20,43,0.16)");
  gradient.addColorStop(1, "rgba(21,20,43,0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, width, height);
}
