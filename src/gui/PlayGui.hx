package gui;

import src.ProfilerUI;
import hxd.App;
import hxd.res.Image;
import hxd.Window;
import h3d.shader.AlphaMult;
import h3d.shader.ColorKey;
import hxd.snd.WavData;
import gui.GuiControl.HorizSizing;
import src.TimeState;
import format.gif.Data.Block;
import hxd.res.BitmapFont;
import h2d.Text;
import h3d.Vector;
import hxd.fmt.hmd.Data.AnimationEvent;
import h2d.Tile;
import h3d.mat.DepthBuffer;
import h3d.mat.Texture;
import h3d.mat.Material;
import h3d.scene.Mesh;
import h3d.prim.Cube;
import src.DtsObject;
import h2d.Anim;
import h2d.Bitmap;
import src.ResourceLoader;
import src.MarbleGame;
import src.Resource;
import hxd.res.Sound;
import h3d.mat.Texture;
import src.Settings;
import src.Util;

typedef MiddleMessage = {
	ctrl:GuiText,
	age:Float,
}

class PlayGui {
	var scene2d:h2d.Scene;

	public function new() {}

	var timerNumbers:Array<GuiAnim> = [];
	var timerPoint:GuiAnim;
	var timerColon:GuiAnim;

	var gemCountNumbers:Array<GuiAnim> = [];
	var gemCountSlash:GuiImage;
	var gemImageScene:h3d.scene.Scene;
	var gemImageSceneTarget:Texture;
	var gemImageObject:DtsObject;
	var gemImageSceneTargetBitmap:Bitmap;

	var powerupBox:GuiImage;
	var powerupImageScene:h3d.scene.Scene;
	var powerupImageSceneTarget:Texture;
	var powerupImageSceneTargetBitmap:Bitmap;
	var powerupImageObject:DtsObject;

	var RSGOCenterText:Anim;

	var helpTextForeground:GuiText;
	var helpTextBackground:GuiText;
	var alertTextForeground:GuiText;
	var alertTextBackground:GuiText;

	var blastBar:GuiControl;
	var blastFill:GuiImage;
	var blastFrame:GuiImage;

	var imageResources:Array<Resource<Image>> = [];
	var textureResources:Array<Resource<Texture>> = [];
	var soundResources:Array<Resource<Sound>> = [];

	var playGuiCtrl:GuiControl;

	var resizeEv:Void->Void;

	var _init:Bool;

	var fpsMeter:GuiText;

	var middleMessages:Array<MiddleMessage> = [];

	public function dispose() {
		if (_init) {
			playGuiCtrl.dispose();
			gemImageScene.dispose();
			gemImageSceneTarget.dispose();
			gemImageSceneTargetBitmap.remove();
			powerupImageScene.dispose();
			powerupImageSceneTarget.dispose();
			powerupImageSceneTargetBitmap.remove();
			RSGOCenterText.remove();

			for (textureResource in textureResources) {
				textureResource.release();
			}
			for (imageResource in imageResources) {
				imageResource.release();
			}
			for (audioResource in soundResources) {
				audioResource.release();
			}

			Window.getInstance().removeResizeEvent(resizeEv);
		}
	}

	public function init(scene2d:h2d.Scene, game:String, onFinish:Void->Void) {
		this.scene2d = scene2d;
		this._init = true;

		playGuiCtrl = new GuiControl();
		playGuiCtrl.position = new Vector();
		playGuiCtrl.extent = new Vector(640, 480);
		playGuiCtrl.horizSizing = Width;
		playGuiCtrl.vertSizing = Height;

		var numberTiles = [];
		for (i in 0...10) {
			var tile = ResourceLoader.getResource('data/ui/game/numbers/${i}.png', ResourceLoader.getImage, this.imageResources).toTile();
			numberTiles.push(tile);
		}
		for (i in 0...10) {
			var tile = ResourceLoader.getResource('data/ui/game/numbers/${i}_green.png', ResourceLoader.getImage, this.imageResources).toTile();
			numberTiles.push(tile);
		}
		for (i in 0...10) {
			var tile = ResourceLoader.getResource('data/ui/game/numbers/${i}_red.png', ResourceLoader.getImage, this.imageResources).toTile();
			numberTiles.push(tile);
		}

		for (i in 0...7) {
			timerNumbers.push(new GuiAnim(numberTiles));
		}

		for (i in 0...4) {
			gemCountNumbers.push(new GuiAnim(numberTiles));
		}

		var rsgo = [];
		rsgo.push(ResourceLoader.getResource("data/ui/game/ready.png", ResourceLoader.getImage, this.imageResources).toTile());
		rsgo.push(ResourceLoader.getResource("data/ui/game/set.png", ResourceLoader.getImage, this.imageResources).toTile());
		rsgo.push(ResourceLoader.getResource("data/ui/game/go.png", ResourceLoader.getImage, this.imageResources).toTile());
		rsgo.push(ResourceLoader.getResource("data/ui/game/outofbounds.png", ResourceLoader.getImage, this.imageResources).toTile());
		RSGOCenterText = new Anim(rsgo, 0, scene2d);

		powerupBox = new GuiImage(ResourceLoader.getResource('data/ui/game/powerup.png', ResourceLoader.getImage, this.imageResources).toTile());
		initTimer();
		initGemCounter(() -> {
			onFinish();
		});
		initCenterText();
		initPowerupBox();
		if (game == 'ultra')
			initBlastBar();
		initTexts();
		if (Settings.optionsSettings.frameRateVis)
			initFPSMeter();

		if (Util.isTouchDevice()) {
			MarbleGame.instance.touchInput.showControls(this.playGuiCtrl, game == 'ultra');
		}

		playGuiCtrl.render(scene2d);

		resizeEv = () -> {
			var wnd = Window.getInstance();
			playGuiCtrl.render(MarbleGame.canvas.scene2d);
			powerupImageSceneTargetBitmap.x = wnd.width - 88;
		};

		Window.getInstance().addResizeEvent(resizeEv);
	}

	public function initTimer() {
		var timerCtrl = new GuiControl();
		timerCtrl.horizSizing = HorizSizing.Center;
		timerCtrl.position = new Vector(215, 1);
		timerCtrl.extent = new Vector(234, 58);

		var timerTransparency = new GuiImage(ResourceLoader.getResource('data/ui/game/transparency.png', ResourceLoader.getImage, this.imageResources)
			.toTile());
		timerTransparency.position = new Vector(14, -7);
		timerTransparency.extent = new Vector(228, 71);
		timerTransparency.doClipping = false;
		timerCtrl.addChild(timerTransparency);

		timerNumbers[0].position = new Vector(23, 0);
		timerNumbers[0].extent = new Vector(43, 55);

		timerNumbers[1].position = new Vector(47, 0);
		timerNumbers[1].extent = new Vector(43, 55);

		var colonCols = [
			ResourceLoader.getResource('data/ui/game/numbers/colon.png', ResourceLoader.getImage, this.imageResources).toTile(),
			ResourceLoader.getResource('data/ui/game/numbers/colon_green.png', ResourceLoader.getImage, this.imageResources).toTile(),
			ResourceLoader.getResource('data/ui/game/numbers/colon_red.png', ResourceLoader.getImage, this.imageResources).toTile()
		];

		timerColon = new GuiAnim(colonCols);
		timerColon.position = new Vector(67, 0);
		timerColon.extent = new Vector(43, 55);

		timerNumbers[2].position = new Vector(83, 0);
		timerNumbers[2].extent = new Vector(43, 55);

		timerNumbers[3].position = new Vector(107, 0);
		timerNumbers[3].extent = new Vector(43, 55);

		var pointCols = [
			ResourceLoader.getResource('data/ui/game/numbers/point.png', ResourceLoader.getImage, this.imageResources).toTile(),
			ResourceLoader.getResource('data/ui/game/numbers/point_green.png', ResourceLoader.getImage, this.imageResources).toTile(),
			ResourceLoader.getResource('data/ui/game/numbers/point_red.png', ResourceLoader.getImage, this.imageResources).toTile()
		];

		timerPoint = new GuiAnim(pointCols);
		timerPoint.position = new Vector(127, 0);
		timerPoint.extent = new Vector(43, 55);

		timerNumbers[4].position = new Vector(143, 0);
		timerNumbers[4].extent = new Vector(43, 55);

		timerNumbers[5].position = new Vector(167, 0);
		timerNumbers[5].extent = new Vector(43, 55);

		timerNumbers[6].position = new Vector(191, 0);
		timerNumbers[6].extent = new Vector(43, 55);

		timerCtrl.addChild(timerNumbers[0]);
		timerCtrl.addChild(timerNumbers[1]);
		timerCtrl.addChild(timerColon);
		timerCtrl.addChild(timerNumbers[2]);
		timerCtrl.addChild(timerNumbers[3]);
		timerCtrl.addChild(timerPoint);
		timerCtrl.addChild(timerNumbers[4]);
		timerCtrl.addChild(timerNumbers[5]);
		timerCtrl.addChild(timerNumbers[6]);

		playGuiCtrl.addChild(timerCtrl);
	}

	public function initCenterText() {
		RSGOCenterText.x = scene2d.width / 2 - RSGOCenterText.frames[0].width * Settings.uiScale / 2;
		RSGOCenterText.y = scene2d.height * 0.3; // - RSGOCenterText.frames[0].height / 2;
		RSGOCenterText.setScale(Settings.uiScale);
	}

	public function setCenterText(identifier:String) {
		if (identifier == 'none') {
			this.RSGOCenterText.visible = false;
		} else if (identifier == 'ready') {
			this.RSGOCenterText.visible = true;
			this.RSGOCenterText.currentFrame = 0;
			RSGOCenterText.x = scene2d.width / 2 - RSGOCenterText.frames[0].width * Settings.uiScale / 2;
		} else if (identifier == 'set') {
			this.RSGOCenterText.visible = true;
			this.RSGOCenterText.currentFrame = 1;
			RSGOCenterText.x = scene2d.width / 2 - RSGOCenterText.frames[1].width * Settings.uiScale / 2;
		} else if (identifier == 'go') {
			this.RSGOCenterText.visible = true;
			this.RSGOCenterText.currentFrame = 2;
			RSGOCenterText.x = scene2d.width / 2 - RSGOCenterText.frames[2].width * Settings.uiScale / 2;
		} else if (identifier == 'outofbounds') {
			this.RSGOCenterText.visible = true;
			this.RSGOCenterText.currentFrame = 3;
			RSGOCenterText.x = scene2d.width / 2 - RSGOCenterText.frames[3].width * Settings.uiScale / 2;
		}
	}

	public function initGemCounter(onFinish:Void->Void) {
		gemCountNumbers[0].position = new Vector(30, 0);
		gemCountNumbers[0].extent = new Vector(43, 55);

		gemCountNumbers[1].position = new Vector(54, 0);
		gemCountNumbers[1].extent = new Vector(43, 55);

		gemCountSlash = new GuiImage(ResourceLoader.getResource('data/ui/game/numbers/slash.png', ResourceLoader.getImage, this.imageResources).toTile());
		gemCountSlash.position = new Vector(75, 0);
		gemCountSlash.extent = new Vector(43, 55);

		gemCountNumbers[2].position = new Vector(96, 0);
		gemCountNumbers[2].extent = new Vector(43, 55);

		gemCountNumbers[3].position = new Vector(120, 0);
		gemCountNumbers[3].extent = new Vector(43, 55);

		playGuiCtrl.addChild(gemCountNumbers[0]);
		playGuiCtrl.addChild(gemCountNumbers[1]);
		playGuiCtrl.addChild(gemCountSlash);
		playGuiCtrl.addChild(gemCountNumbers[2]);
		playGuiCtrl.addChild(gemCountNumbers[3]);

		this.gemImageScene = new h3d.scene.Scene();
		// var gemImageRenderer = cast(this.gemImageScene.renderer, h3d.scene.Renderer);
		// gemImageRenderer.skyMode = Hide;

		gemImageSceneTarget = new Texture(60, 60, [Target]);
		gemImageSceneTarget.depthBuffer = new DepthBuffer(60, 60);

		gemImageSceneTargetBitmap = new Bitmap(Tile.fromTexture(gemImageSceneTarget), scene2d);
		gemImageSceneTargetBitmap.x = -8 * Settings.uiScale;
		gemImageSceneTargetBitmap.y = -8 * Settings.uiScale;
		gemImageSceneTargetBitmap.setScale(Settings.uiScale);
		// gemImageSceneTargetBitmap.blendMode = None;
		// gemImageSceneTargetBitmap.addShader(new ColorKey());

		var GEM_COLORS = ["blue", "red", "yellow", "purple", "green", "turquoise", "orange", "black"];
		var gemColor = GEM_COLORS[Math.floor(Math.random() * GEM_COLORS.length)];

		gemImageObject = new DtsObject();
		gemImageObject.dtsPath = "data/shapes/items/gem.dts";
		gemImageObject.ambientRotate = true;
		gemImageObject.showSequences = false;
		gemImageObject.matNameOverride.set('base.gem', gemColor + ".gem");
		// gemImageObject.matNameOverride.set("base.gem", "base.gem.");
		gemImageObject.ambientSpinFactor /= -2;
		// ["base.gem"] = color + ".gem";
		ResourceLoader.load("shapes/items/gem.dts").entry.load(() -> {
			ResourceLoader.load("shapes/items/" + gemColor + ".gem.png").entry.load(() -> {
				gemImageObject.init(null, () -> {
					for (mat in gemImageObject.materials) {
						mat.mainPass.enableLights = false;

						// Huge hacks
						if (mat.blendMode != Add) {
							var alphaShader = new h3d.shader.AlphaChannel();
							mat.mainPass.addShader(alphaShader);
						}
					}
					gemImageScene.addChild(gemImageObject);
					var gemImageCenter = gemImageObject.getBounds().getCenter();

					gemImageScene.camera.pos = new Vector(0, 3, gemImageCenter.z);
					gemImageScene.camera.target = new Vector(gemImageCenter.x, gemImageCenter.y, gemImageCenter.z);
					onFinish();
				});
			});
		});
	}

	function initPowerupBox() {
		powerupBox.position = new Vector(538, 6);
		powerupBox.extent = new Vector(97, 96);
		powerupBox.horizSizing = Left;

		playGuiCtrl.addChild(powerupBox);

		this.powerupImageScene = new h3d.scene.Scene();
		// var powerupImageRenderer = cast(this.powerupImageScene.renderer, h3d.scene.pbr.Renderer);
		// powerupImageRenderer.skyMode = Hide;

		powerupImageSceneTarget = new Texture(68, 67, [Target]);
		powerupImageSceneTarget.depthBuffer = new DepthBuffer(68, 67);

		powerupImageSceneTargetBitmap = new Bitmap(Tile.fromTexture(powerupImageSceneTarget), scene2d);
		powerupImageSceneTargetBitmap.x = scene2d.width - 88 * Settings.uiScale;
		powerupImageSceneTargetBitmap.y = 18 * Settings.uiScale;
		powerupImageSceneTargetBitmap.setScale(Settings.uiScale);
	}

	function initTexts() {
		var domcasual32fontdata = ResourceLoader.getFileEntry("data/font/DomCasualD.fnt");
		var domcasual32b = new BitmapFont(domcasual32fontdata.entry);
		@:privateAccess domcasual32b.loader = ResourceLoader.loader;
		var bfont = domcasual32b.toSdfFont(cast 26 * Settings.uiScale, MultiChannel);

		var helpTextCtrl = new GuiControl();
		helpTextCtrl.position = new Vector(0, 210);
		helpTextCtrl.extent = new Vector(640, 60);
		helpTextCtrl.vertSizing = Center;
		helpTextCtrl.horizSizing = Width;

		helpTextBackground = new GuiText(bfont);
		helpTextBackground.text.textColor = 0x777777;
		helpTextBackground.position = new Vector(1, 1);
		helpTextBackground.extent = new Vector(640, 14);
		helpTextBackground.vertSizing = Height;
		helpTextBackground.horizSizing = Width;
		helpTextBackground.justify = Center;

		helpTextForeground = new GuiText(bfont);
		helpTextForeground.text.textColor = 0xFFFFFF;
		helpTextForeground.position = new Vector(0, 0);
		helpTextForeground.extent = new Vector(640, 16);
		helpTextForeground.vertSizing = Height;
		helpTextForeground.horizSizing = Width;
		helpTextForeground.justify = Center;

		helpTextCtrl.addChild(helpTextBackground);
		helpTextCtrl.addChild(helpTextForeground);

		var alertTextCtrl = new GuiControl();
		alertTextCtrl.position = new Vector(0, 371);
		alertTextCtrl.extent = new Vector(640, 105);
		alertTextCtrl.vertSizing = Top;
		alertTextCtrl.horizSizing = Width;

		alertTextBackground = new GuiText(bfont);
		alertTextBackground.text.textColor = 0x776622;
		alertTextBackground.position = new Vector(1, 1);
		alertTextBackground.extent = new Vector(640, 32);
		alertTextBackground.vertSizing = Height;
		alertTextBackground.horizSizing = Width;
		alertTextBackground.justify = Center;

		alertTextForeground = new GuiText(bfont);
		alertTextForeground.text.textColor = 0xffEE99;
		alertTextForeground.position = new Vector(0, 0);
		alertTextForeground.extent = new Vector(640, 32);
		alertTextForeground.vertSizing = Height;
		alertTextForeground.horizSizing = Width;
		alertTextForeground.justify = Center;

		alertTextCtrl.addChild(alertTextBackground);
		alertTextCtrl.addChild(alertTextForeground);

		playGuiCtrl.addChild(helpTextCtrl);
		playGuiCtrl.addChild(alertTextCtrl);
	}

	function initFPSMeter() {
		var domcasual32fontdata = ResourceLoader.getFileEntry("data/font/DomCasualD.fnt");
		var domcasual32b = new BitmapFont(domcasual32fontdata.entry);
		@:privateAccess domcasual32b.loader = ResourceLoader.loader;
		var bfont = domcasual32b.toSdfFont(cast 26 * Settings.uiScale, MultiChannel);

		var fpsMeterCtrl = new GuiImage(ResourceLoader.getResource("data/ui/game/transparency-fps.png", ResourceLoader.getImage, this.imageResources)
			.toTile());
		fpsMeterCtrl.position = new Vector(544, 448);
		fpsMeterCtrl.horizSizing = Left;
		fpsMeterCtrl.vertSizing = Top;
		fpsMeterCtrl.extent = new Vector(96, 32);

		fpsMeter = new GuiText(bfont);
		fpsMeter.horizSizing = Width;
		fpsMeter.vertSizing = Height;
		fpsMeter.position = new Vector(10, 3);
		fpsMeter.text.textColor = 0;
		fpsMeter.extent = new Vector(96, 32);
		fpsMeterCtrl.addChild(fpsMeter);

		playGuiCtrl.addChild(fpsMeterCtrl);
	}

	function initBlastBar() {
		blastBar = new GuiControl();
		blastBar.position = new Vector(6, 445);
		blastBar.extent = new Vector(120, 28);
		blastBar.vertSizing = Top;
		this.playGuiCtrl.addChild(blastBar);

		blastFill = new GuiImage(ResourceLoader.getResource("data/ui/game/blastbar_bargreen.png", ResourceLoader.getImage, this.imageResources).toTile());
		blastFill.position = new Vector(5, 5);
		blastFill.extent = new Vector(58, 17);
		blastFill.doClipping = false;
		blastBar.addChild(blastFill);

		blastFrame = new GuiImage(ResourceLoader.getResource("data/ui/game/blastbar.png", ResourceLoader.getImage, this.imageResources).toTile());
		blastFrame.position = new Vector(0, 0);
		blastFrame.extent = new Vector(120, 28);
		blastBar.addChild(blastFrame);
	}

	public function setBlastValue(value:Float) {
		if (value <= 1) {
			if (blastFill.extent.y == 16) { // Was previously charged
				blastFrame.bmp.tile = ResourceLoader.getResource("data/ui/game/blastbar.png", ResourceLoader.getImage, this.imageResources).toTile();
			}
			var oldVal = blastFill.extent.x;
			blastFill.extent = new Vector(Util.lerp(0, 110, value), 17);
			if (oldVal < 22 && blastFill.extent.x >= 22) {
				blastFill.bmp.tile = ResourceLoader.getResource("data/ui/game/blastbar_bargreen.png", ResourceLoader.getImage, this.imageResources).toTile();
				MarbleGame.instance.touchInput.blastbutton.setEnabled(true);
			}
			if (oldVal >= 22 && blastFill.extent.x < 22) {
				blastFill.bmp.tile = ResourceLoader.getResource("data/ui/game/blastbar_bargray.png", ResourceLoader.getImage, this.imageResources).toTile();
				MarbleGame.instance.touchInput.blastbutton.setEnabled(false);
			}
		} else {
			blastFill.extent = new Vector(0, 16); // WE will just use this extra number to store whether it was previously charged or not
			blastFrame.bmp.tile = ResourceLoader.getResource("data/ui/game/blastbar_charged.png", ResourceLoader.getImage, this.imageResources).toTile();
			MarbleGame.instance.touchInput.blastbutton.setEnabled(true);
		}
		this.blastBar.render(scene2d);
	}

	public function setHelpTextOpacity(value:Float) {
		@:privateAccess helpTextForeground.text._textColorVec.a = value;
		@:privateAccess helpTextBackground.text._textColorVec.a = value;
	}

	public function setAlertTextOpacity(value:Float) {
		@:privateAccess alertTextForeground.text._textColorVec.a = value;
		@:privateAccess alertTextBackground.text._textColorVec.a = value;
	}

	public function setAlertText(text:String) {
		this.alertTextForeground.text.text = text;
		this.alertTextBackground.text.text = text;
		// alertTextBackground.render(scene2d);
		// alertTextForeground.x = scene2d.width / 2 - alertTextForeground.textWidth / 2;
		// alertTextForeground.y = scene2d.height - 102;
		// alertTextBackground.x = scene2d.width / 2 - alertTextBackground.textWidth / 2 + 1;
		// alertTextBackground.y = scene2d.height - 102 + 1;
	}

	public function setHelpText(text:String) {
		this.helpTextForeground.text.text = text;
		this.helpTextBackground.text.text = text;
		// helpTextBackground.render(scene2d);
		// helpTextForeground.x = scene2d.width / 2 - helpTextForeground.textWidth / 2;
		// helpTextForeground.y = scene2d.height * 0.45;
		// helpTextBackground.x = scene2d.width / 2 - helpTextBackground.textWidth / 2 + 1;
		// helpTextBackground.y = scene2d.height * 0.45 + 1;
	}

	public function setPowerupImage(powerupIdentifier:String) {
		this.powerupImageScene.removeChildren();
		if (powerupIdentifier == "SuperJump") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/items/superjump.dts";
		} else if (powerupIdentifier == "SuperSpeed") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/items/superspeed.dts";
		} else if (powerupIdentifier == "ShockAbsorber") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/items/shockabsorber.dts";
		} else if (powerupIdentifier == "SuperBounce") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/items/superbounce.dts";
		} else if (powerupIdentifier == "Helicopter") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/images/helicopter.dts";
		} else if (powerupIdentifier == "MegaMarble") {
			powerupImageObject = new DtsObject();
			powerupImageObject.dtsPath = "data/shapes/items/megamarble.dts";
		} else {
			powerupIdentifier = "";
			this.powerupImageObject = null;
		}

		if (powerupIdentifier != "") {
			powerupImageObject.ambientRotate = true;
			powerupImageObject.ambientSpinFactor /= 2;
			powerupImageObject.showSequences = false;
			powerupImageObject.init(null, () -> {
				for (mat in powerupImageObject.materials) {
					mat.mainPass.enableLights = false;
					if (mat.blendMode != Alpha && mat.blendMode != Add)
						mat.mainPass.addShader(new h3d.shader.AlphaChannel());
				}
				powerupImageScene.addChild(powerupImageObject);
				var powerupImageCenter = powerupImageObject.getBounds().getCenter();

				powerupImageScene.camera.pos = new Vector(0, 4, powerupImageCenter.z);
				powerupImageScene.camera.target = new Vector(powerupImageCenter.x, powerupImageCenter.y, powerupImageCenter.z);
			});
		}
	}

	public function formatGemCounter(collected:Int, total:Int) {
		if (total == 0) {
			for (number in gemCountNumbers) {
				number.anim.visible = false;
			}
			gemCountSlash.bmp.visible = false;
			gemImageSceneTargetBitmap.visible = false;
		} else {
			for (number in gemCountNumbers) {
				number.anim.visible = true;
			}
			gemCountSlash.bmp.visible = true;
			gemImageSceneTargetBitmap.visible = true;
		}

		var totalTenths = Math.floor(total / 10);
		var totalOnes = total % 10;

		var collectedTenths = Math.floor(collected / 10);
		var collectedOnes = collected % 10;

		gemCountNumbers[0].anim.currentFrame = collectedTenths;
		gemCountNumbers[1].anim.currentFrame = collectedOnes;
		gemCountNumbers[2].anim.currentFrame = totalTenths;
		gemCountNumbers[3].anim.currentFrame = totalOnes;
	}

	// 0: default
	// 1: green
	// 2: red
	public function formatTimer(time:Float, color:Int = 0) {
		var et = time * 1000;
		var thousandth = et % 10;
		var hundredth = Math.floor((et % 1000) / 10);
		var totalSeconds = Math.floor(et / 1000);
		var seconds = totalSeconds % 60;
		var minutes = (totalSeconds - seconds) / 60;

		var secondsOne = seconds % 10;
		var secondsTen = (seconds - secondsOne) / 10;
		var minutesOne = minutes % 10;
		var minutesTen = (minutes - minutesOne) / 10;
		var hundredthOne = hundredth % 10;
		var hundredthTen = (hundredth - hundredthOne) / 10;

		timerNumbers[0].anim.currentFrame = minutesTen + color * 10;
		timerNumbers[1].anim.currentFrame = minutesOne + color * 10;
		timerNumbers[2].anim.currentFrame = secondsTen + color * 10;
		timerNumbers[3].anim.currentFrame = secondsOne + color * 10;
		timerNumbers[4].anim.currentFrame = hundredthTen + color * 10;
		timerNumbers[5].anim.currentFrame = hundredthOne + color * 10;
		timerNumbers[6].anim.currentFrame = thousandth + color * 10;

		timerPoint.anim.currentFrame = color;
		timerColon.anim.currentFrame = color;
	}

	public function render(engine:h3d.Engine) {
		engine.pushTarget(this.gemImageSceneTarget);

		engine.clear(0, 1);
		this.gemImageScene.render(engine);

		engine.popTarget();
		engine.pushTarget(this.powerupImageSceneTarget);

		engine.clear(0, 1);
		this.powerupImageScene.render(engine);

		engine.popTarget();
	}

	public function update(timeState:TimeState) {
		this.gemImageObject.update(timeState);
		this.gemImageScene.setElapsedTime(timeState.dt);
		if (this.powerupImageObject != null)
			this.powerupImageObject.update(timeState);
		this.powerupImageScene.setElapsedTime(timeState.dt);

		if (this.fpsMeter != null) {
			this.fpsMeter.text.text = '${Math.floor(ProfilerUI.instance.fps)} fps';
		}
		this.updateMiddleMessages(timeState.dt);
	}

	function updateMiddleMessages(dt:Float) {
		var itermessages = this.middleMessages.copy();
		if (itermessages.length > 0) {
			var thismsg = itermessages.shift();
			thismsg.age += dt;
			if (thismsg.age > 0.6) {
				this.middleMessages.remove(thismsg);
				thismsg.ctrl.parent.removeChild(thismsg.ctrl); // Delete it
			} else {
				if (thismsg.age >= 0.3) {
					thismsg.ctrl.text.alpha = 1 - (thismsg.age - 0.3) / 0.3;
				}
				thismsg.ctrl.text.y -= (0.1 / playGuiCtrl.extent.y) * scene2d.height;
			}
		}
	}

	public function addMiddleMessage(text:String, color:Int) {
		var markerFelt32fontdata = ResourceLoader.getFileEntry("data/font/MarkerFelt.fnt");
		var markerFelt32b = new BitmapFont(markerFelt32fontdata.entry);
		@:privateAccess markerFelt32b.loader = ResourceLoader.loader;
		var markerFelt32 = markerFelt32b.toSdfFont(cast 44 * Settings.uiScale, MultiChannel);

		var middleMsg = new GuiText(markerFelt32);
		middleMsg.position = new Vector(200, 50);
		middleMsg.extent = new Vector(400, 100);
		middleMsg.horizSizing = Center;
		middleMsg.vertSizing = Center;
		middleMsg.text.text = text;
		middleMsg.justify = Center;
		middleMsg.text.textColor = color;
		middleMsg.text.filter = new h2d.filter.DropShadow(1.414, 0.785, 0x000000F, 1, 0, 0.4, 1, true);
		this.playGuiCtrl.addChild(middleMsg);
		middleMsg.render(scene2d);
		middleMsg.text.y -= (25 / playGuiCtrl.extent.y) * scene2d.height;

		this.middleMessages.push({ctrl: middleMsg, age: 0});
	}
}
