package src;

#if js
import gui.MainMenuGui;
#else
import gui.ReplayCenterGui;
#end
import gui.ReplayNameDlg;
import collision.Collision;
import shapes.MegaMarble;
import shapes.Blast;
import shapes.Glass;
import gui.OOBInsultGui;
import shapes.Checkpoint;
import triggers.CheckpointTrigger;
import shapes.EasterEgg;
import shapes.Sign;
import triggers.TeleportTrigger;
import triggers.DestinationTrigger;
import shapes.Nuke;
import shapes.Magnet;
import src.Replay;
import gui.Canvas;
import hxd.snd.Channel;
import hxd.res.Sound;
import src.ResourceLoader;
import src.AudioManager;
import src.Settings;
import gui.LoadingGui;
import gui.PlayMissionGui;
import src.MarbleGame;
import gui.EndGameGui;
#if hlsdl
import sdl.Cursor;
#end
#if hldx
import dx.Cursor;
#end
import src.ForceObject;
import shaders.DirLight;
import h3d.col.Bounds;
import triggers.HelpTrigger;
import triggers.InBoundsTrigger;
import triggers.OutOfBoundsTrigger;
import shapes.Trapdoor;
import shapes.Oilslick;
import shapes.Tornado;
import shapes.TimeTravel;
import shapes.SuperSpeed;
import shapes.ShockAbsorber;
import shapes.LandMine;
import shapes.AntiGravity;
import shapes.SmallDuctFan;
import shapes.DuctFan;
import shapes.Helicopter;
import shapes.TriangleBumper;
import shapes.RoundBumper;
import shapes.SuperBounce;
import shapes.SignCaution;
import shapes.SuperJump;
import shapes.Gem;
import shapes.SignPlain;
import shapes.SignFinish;
import shapes.EndPad;
import shapes.StartPad;
import h3d.Matrix;
import mis.MisParser;
import src.DifBuilder;
import mis.MissionElement;
import src.GameObject;
import triggers.Trigger;
import src.Mission;
import src.TimeState;
import gui.PlayGui;
import src.ParticleSystem.ParticleManager;
import src.Util;
import h3d.Quat;
import shapes.PowerUp;
import collision.SphereCollisionEntity;
import src.Sky;
import h3d.scene.Mesh;
import src.InstanceManager;
import h3d.scene.MeshBatch;
import src.DtsObject;
import src.PathedInterior;
import hxd.Key;
import h3d.Vector;
import src.InteriorObject;
import h3d.scene.Scene;
import collision.CollisionWorld;
import src.Marble;
import src.Resource;
import src.ProfilerUI;
import src.ResourceLoaderWorker;
import haxe.io.Path;
import src.Console;
import src.Gamepad;

class MarbleWorld extends Scheduler {
	public var collisionWorld:CollisionWorld;
	public var instanceManager:InstanceManager;
	public var particleManager:ParticleManager;

	var playGui:PlayGui;
	var loadingGui:LoadingGui;

	public var interiors:Array<InteriorObject> = [];
	public var pathedInteriors:Array<PathedInterior> = [];
	public var marbles:Array<Marble> = [];
	public var dtsObjects:Array<DtsObject> = [];
	public var forceObjects:Array<ForceObject> = [];
	public var triggers:Array<Trigger> = [];
	public var gems:Array<Gem> = [];
	public var namedObjects:Map<String, {obj:DtsObject, elem:MissionElementBase}> = [];

	var shapeImmunity:Array<DtsObject> = [];
	var shapeOrTriggerInside:Array<GameObject> = [];

	public var timeState:TimeState = new TimeState();
	public var bonusTime:Float = 0;
	public var sky:Sky;

	var endPadElement:MissionElementStaticShape;
	var endPad:EndPad;
	var skyElement:MissionElementSky;

	// Lighting
	public var ambient:Vector;
	public var dirLight:Vector;
	public var dirLightDir:Vector;

	public var scene:Scene;
	public var scene2d:h2d.Scene;
	public var mission:Mission;
	public var game:String;

	public var marble:Marble;
	public var worldOrientation:Quat;
	public var currentUp = new Vector(0, 0, 1);
	public var outOfBounds:Bool = false;
	public var outOfBoundsTime:TimeState;
	public var finishTime:TimeState;
	public var finishPitch:Float;
	public var finishYaw:Float;
	public var totalGems:Int = 0;
	public var gemCount:Int = 0;
	public var blastAmount:Float = 0;

	public var cursorLock:Bool = true;

	var timeTravelSound:Channel;
	var alarmSound:Channel;

	var helpTextTimeState:Float = -1e8;
	var alertTextTimeState:Float = -1e8;

	var respawnPressedTime:Float = -1e8;

	// Orientation
	var orientationChangeTime = -1e8;
	var oldOrientationQuat = new Quat();

	public var newOrientationQuat = new Quat();

	// Checkpoint
	var currentCheckpoint:{obj:DtsObject, elem:MissionElementBase} = null;
	var currentCheckpointTrigger:CheckpointTrigger = null;
	var checkpointCollectedGems:Map<Gem, Bool> = [];
	var checkpointHeldPowerup:PowerUp = null;
	var checkpointUp:Vector = null;
	var cheeckpointBlast:Float = 0;

	// Replay
	public var replay:Replay;
	public var isWatching:Bool = false;
	public var isRecording:Bool = false;

	// Loading
	var resourceLoadFuncs:Array<(() -> Void)->Void> = [];

	public var _disposed:Bool = false;

	public var _ready:Bool = false;

	var _loadingLength:Int = 0;

	var _resourcesLoaded:Int = 0;

	var textureResources:Array<Resource<h3d.mat.Texture>> = [];
	var soundResources:Array<Resource<Sound>> = [];

	var lock:Bool = false;

	public function new(scene:Scene, scene2d:h2d.Scene, mission:Mission, record:Bool = false) {
		this.scene = scene;
		this.scene2d = scene2d;
		this.mission = mission;
		this.game = mission.game.toLowerCase();
		this.replay = new Replay(mission.path);
		this.isRecording = record;
	}

	public function init() {
		initLoading();
	}

	public function initLoading() {
		Console.log("*** LOADING MISSION: " + mission.path);
		this.loadingGui = new LoadingGui(this.mission.title, this.mission.game);
		MarbleGame.canvas.setContent(this.loadingGui);

		function scanMission(simGroup:MissionElementSimGroup) {
			for (element in simGroup.elements) {
				if ([
					MissionElementType.InteriorInstance,
					MissionElementType.Item,
					MissionElementType.PathedInterior,
					MissionElementType.StaticShape,
					MissionElementType.TSStatic,
					MissionElementType.Sky
				].contains(element._type)) {
					// this.loadingState.total++;

					// Override the end pad element. We do this because only the last finish pad element will actually do anything.
					if (element._type == MissionElementType.StaticShape) {
						var so:MissionElementStaticShape = cast element;
						if (so.datablock.toLowerCase() == 'endpad')
							this.endPadElement = so;
					}

					if (element._type == Sky) {
						this.skyElement = cast element;
					}
				} else if (element._type == MissionElementType.SimGroup) {
					scanMission(cast element);
				}
			}
		};
		this.mission.load();
		scanMission(this.mission.root);
		this.resourceLoadFuncs.push(fwd -> this.initScene(fwd));
		this.resourceLoadFuncs.push(fwd -> this.initMarble(fwd));
		this.resourceLoadFuncs.push(fwd -> {
			this.addSimGroup(this.mission.root);
			this._loadingLength = resourceLoadFuncs.length;
			fwd();
		});
		this.resourceLoadFuncs.push(fwd -> this.loadMusic(fwd));
		this._loadingLength = resourceLoadFuncs.length;
	}

	public function loadMusic(onFinish:Void->Void) {
		var musicFileName = 'sound/music/' + this.mission.missionInfo.music;
		ResourceLoader.load(musicFileName).entry.load(onFinish);
	}

	public function postInit() {
		// Add the sky at the last so that cubemap reflections work
		this.playGui.init(this.scene2d, this.mission.game.toLowerCase(), () -> {
			this.scene.addChild(this.sky);
			this._ready = true;
			var musicFileName = 'data/sound/music/' + this.mission.missionInfo.music;
			AudioManager.playMusic(ResourceLoader.getResource(musicFileName, ResourceLoader.getAudio, this.soundResources), this.mission.missionInfo.music);
			MarbleGame.canvas.clearContent();
			this.endPad.generateCollider();
			this.playGui.formatGemCounter(this.gemCount, this.totalGems);
			Console.log("MISSION LOADED");
			start();
		});
	}

	public function initScene(onFinish:Void->Void) {
		Console.log("Starting scene");
		this.collisionWorld = new CollisionWorld();
		this.playGui = new PlayGui();
		this.instanceManager = new InstanceManager(scene);
		this.particleManager = new ParticleManager(cast this);

		var worker = new ResourceLoaderWorker(() -> {
			var renderer = cast(this.scene.renderer, h3d.scene.fwd.Renderer);

			for (element in mission.root.elements) {
				if (element._type != MissionElementType.Sun)
					continue;

				var sunElement:MissionElementSun = cast element;

				var directionalColor = MisParser.parseVector4(sunElement.color);
				var ambientColor = MisParser.parseVector4(sunElement.ambient);
				if (this.game == "ultra") {
					ambientColor.r *= 1.18;
					ambientColor.g *= 1.06;
					ambientColor.b *= 0.95;
				}
				var sunDirection = MisParser.parseVector3(sunElement.direction);
				sunDirection.x = -sunDirection.x;
				// sunDirection.x = 0;
				// sunDirection.y = 0;
				// sunDirection.z = -sunDirection.z;
				var ls = cast(scene.lightSystem, h3d.scene.fwd.LightSystem);

				ls.ambientLight.load(ambientColor);
				this.ambient = ambientColor;
				// ls.perPixelLighting = false;

				var shadow = scene.renderer.getPass(h3d.pass.DefaultShadowMap);
				shadow.power = 0.5;
				shadow.mode = Dynamic;
				shadow.minDist = 0.1;
				shadow.maxDist = 200;
				shadow.bias = 0;

				var sunlight = new DirLight(sunDirection, scene);
				sunlight.color = directionalColor;

				this.dirLight = directionalColor;
				this.dirLightDir = sunDirection;
			}

			onFinish();
		});
		var filestoload = [
			"particles/bubble.png",
			"particles/saturn.png",
			"particles/smoke.png",
			"particles/spark.png",
			"particles/star.png",
			"particles/twirl.png"
		];

		for (file in filestoload) {
			worker.loadFile(file);
		}

		this.scene.camera.zFar = Math.max(4000, Std.parseFloat(this.skyElement.visibledistance));

		this.sky = new Sky();

		sky.dmlPath = ResourceLoader.getProperFilepath(skyElement.materiallist);

		worker.addTask(fwd -> sky.init(cast this, fwd));
		// worker.addTask(fwd -> {
		// 	scene.addChild(sky);
		// 	return fwd();
		// });

		worker.run();
	}

	public function initMarble(onFinish:Void->Void) {
		Console.log("Initializing marble");
		var worker = new ResourceLoaderWorker(onFinish);
		var marblefiles = [
			"particles/star.png",
			"particles/smoke.png",
			"sound/rolling_hard.wav",
			"sound/sliding.wav",
			"sound/superbounceactive.wav",
			"sound/forcefield.wav",
			"sound/use_gyrocopter.wav",
			"sound/bumperding1.wav",
			"sound/bumper1.wav",
			"sound/jump.wav",
			"sound/mega_roll.wav",
			"sound/bouncehard1.wav",
			"sound/bouncehard2.wav",
			"sound/bouncehard3.wav",
			"sound/bouncehard4.wav",
			"sound/spawn.wav",
			"sound/ready.wav",
			"sound/set.wav",
			"sound/go.wav",
			"sound/alarm.wav",
			"sound/alarm_timeout.wav",
			"sound/missinggems.wav",
			"shapes/images/glow_bounce.dts",
			"shapes/images/glow_bounce.png",
			"shapes/images/helicopter.dts",
			"shapes/images/helicopter.jpg",
			"shapes/pads/white.jpg", // These irk us a lot because ifl shit
			"shapes/pads/red.jpg",
			"shapes/pads/blue.jpg",
			"shapes/pads/green.jpg",
			"shapes/items/gem.dts", // Ew ew
			"shapes/items/gemshine.png",
			"shapes/items/enviro1.jpg",
		];
		if (this.game == "ultra") {
			marblefiles.push("shapes/balls/pack1/marble20.normal.png");
			marblefiles.push("shapes/balls/pack1/marble18.normal.png");
			marblefiles.push("shapes/balls/pack1/marble01.normal.png");
			marblefiles.push("sound/blast.wav");
		}
		// Hacky
		marblefiles.push(StringTools.replace(Settings.optionsSettings.marbleModel, "data/", ""));
		if (Settings.optionsSettings.marbleCategoryIndex == 0)
			marblefiles.push("shapes/balls/" + Settings.optionsSettings.marbleSkin + ".marble.png");
		else
			marblefiles.push("shapes/balls/pack1/" + Settings.optionsSettings.marbleSkin + ".marble.png");
		for (file in marblefiles) {
			worker.loadFile(file);
		}
		worker.addTask(fwd -> {
			var marble = new Marble();
			marble.controllable = true;
			this.addMarble(marble, fwd);
		});
		worker.run();
	}

	public function start() {
		Console.log("LEVEL START");
		restart(true);
		for (interior in this.interiors)
			interior.onLevelStart();
		for (shape in this.dtsObjects)
			shape.onLevelStart();
	}

	public function restart(full:Bool = false) {
		Console.log("LEVEL RESTART");
		if (!full && this.currentCheckpoint != null) {
			this.loadCheckpointState();
			return 0; // Load checkpoint
		}

		if (!this.isWatching) {
			this.replay.clear();
		} else
			this.replay.rewind();

		this.timeState.currentAttemptTime = 0;
		this.timeState.gameplayClock = 0;
		this.bonusTime = 0;
		this.outOfBounds = false;
		this.blastAmount = 0;
		this.outOfBoundsTime = null;
		this.finishTime = null;
		if (this.alarmSound != null) {
			this.alarmSound.stop();
			this.alarmSound = null;
		}

		this.currentCheckpoint = null;
		this.currentCheckpointTrigger = null;
		this.checkpointCollectedGems.clear();
		this.checkpointHeldPowerup = null;
		this.checkpointUp = null;
		this.cheeckpointBlast = 0;

		if (this.endPad != null)
			this.endPad.inFinish = false;
		if (this.totalGems > 0) {
			this.gemCount = 0;
			this.playGui.formatGemCounter(this.gemCount, this.totalGems);
		}

		// Record/Playback trapdoor and landmine states
		if (full) {
			var tidx = 0;
			var lidx = 0;
			for (dtss in this.dtsObjects) {
				if (dtss is Trapdoor) {
					var trapdoor:Trapdoor = cast dtss;
					if (!this.isWatching) {
						this.replay.recordTrapdoorState(trapdoor.lastContactTime - this.timeState.timeSinceLoad, trapdoor.lastDirection,
							trapdoor.lastCompletion);
					} else {
						var state = this.replay.getTrapdoorState(tidx);
						trapdoor.lastContactTime = state.lastContactTime + this.timeState.timeSinceLoad;
						trapdoor.lastDirection = state.lastDirection;
						trapdoor.lastCompletion = state.lastCompletion;
					}
					tidx++;
				}
				if (dtss is LandMine) {
					var landmine:LandMine = cast dtss;
					if (!this.isWatching) {
						this.replay.recordLandMineState(landmine.disappearTime - this.timeState.timeSinceLoad);
					} else {
						landmine.disappearTime = this.replay.getLandMineState(lidx) + this.timeState.timeSinceLoad;
					}
					lidx++;
				}
			}
		}

		var startquat = this.getStartPositionAndOrientation();

		this.marble.setPosition(startquat.position.x, startquat.position.y, startquat.position.z + 3);
		var oldtransform = this.marble.collider.transform.clone();
		oldtransform.setPosition(startquat.position);
		this.marble.collider.setTransform(oldtransform);
		this.marble.reset();

		var euler = startquat.quat.toEuler();
		this.marble.camera.init(cast this);
		this.marble.camera.CameraYaw = euler.z + Math.PI / 2;
		this.marble.camera.CameraPitch = 0.45;
		this.marble.camera.nextCameraPitch = 0.45;
		this.marble.camera.nextCameraYaw = euler.z + Math.PI / 2;
		this.marble.camera.oob = false;
		this.marble.camera.finish = false;
		this.marble.mode = Start;
		this.marble.startPad = cast startquat.pad;
		sky.follow = marble.camera;

		var missionInfo:MissionElementScriptObject = cast this.mission.root.elements.filter((element) -> element._type == MissionElementType.ScriptObject
			&& element._name == "MissionInfo")[0];
		if (missionInfo.starthelptext != null)
			displayHelp(missionInfo.starthelptext); // Show the start help text

		for (shape in dtsObjects)
			shape.reset();
		for (interior in this.interiors)
			interior.reset();

		this.currentUp = new Vector(0, 0, 1);
		this.orientationChangeTime = -1e8;
		this.oldOrientationQuat = new Quat();
		this.newOrientationQuat = new Quat();
		this.deselectPowerUp();

		AudioManager.playSound(ResourceLoader.getResource('data/sound/spawn.wav', ResourceLoader.getAudio, this.soundResources));

		Console.log("State Start");
		this.clearSchedule();
		this.schedule(0.5, () -> {
			// setCenterText('ready');
			Console.log("State Ready");
			AudioManager.playSound(ResourceLoader.getResource('data/sound/ready.wav', ResourceLoader.getAudio, this.soundResources));
			return 0;
		});
		this.schedule(2, () -> {
			// setCenterText('set');
			Console.log("State Set");
			AudioManager.playSound(ResourceLoader.getResource('data/sound/set.wav', ResourceLoader.getAudio, this.soundResources));
			return 0;
		});
		this.schedule(3.5, () -> {
			// setCenterText('go');
			Console.log("State Go");
			AudioManager.playSound(ResourceLoader.getResource('data/sound/go.wav', ResourceLoader.getAudio, this.soundResources));
			Console.log("State Play");
			return 0;
		});

		return 0;
	}

	public function updateGameState() {
		if (this.outOfBounds)
			return; // We will update state manually
		if (this.timeState.currentAttemptTime < 0.5) {
			this.playGui.setCenterText('none');
		}
		if ((this.timeState.currentAttemptTime >= 0.5) && (this.timeState.currentAttemptTime < 2)) {
			this.playGui.setCenterText('ready');
		}
		if ((this.timeState.currentAttemptTime >= 2) && (this.timeState.currentAttemptTime < 3.5)) {
			this.playGui.setCenterText('set');
		}
		if ((this.timeState.currentAttemptTime >= 3.5) && (this.timeState.currentAttemptTime < 5.5)) {
			this.playGui.setCenterText('go');
			this.marble.mode = Play;
		}
		if (this.timeState.currentAttemptTime >= 5.5) {
			this.playGui.setCenterText('none');
		}
	}

	function getStartPositionAndOrientation() {
		// The player is spawned at the last start pad in the mission file.
		var startPad = this.dtsObjects.filter(x -> x is StartPad).pop();
		var position:Vector;
		var quat:Quat = new Quat();
		if (startPad != null) {
			// If there's a start pad, start there
			position = startPad.getAbsPos().getPosition();
			quat = startPad.getRotationQuat().clone();
		} else {
			position = new Vector(0, 0, 300);
		}
		return {
			position: position,
			quat: quat,
			pad: startPad
		};
	}

	public function addSimGroup(simGroup:MissionElementSimGroup) {
		if (simGroup.elements.filter((element) -> element._type == MissionElementType.PathedInterior).length != 0) {
			// Create the pathed interior
			resourceLoadFuncs.push(fwd -> {
				src.PathedInterior.createFromSimGroup(simGroup, cast this, pathedInterior -> {
					this.addPathedInterior(pathedInterior, () -> {
						if (pathedInterior == null) {
							fwd();
							Console.error("Unable to load pathed interior");
							return;
						}

						// if (pathedInterior.hasCollision)
						// 	this.physics.addInterior(pathedInterior);
						for (trigger in pathedInterior.triggers) {
							this.triggers.push(trigger);
							this.collisionWorld.addEntity(trigger.collider);
						}
						fwd();
					});
				});
			});

			return;
		}

		for (element in simGroup.elements) {
			switch (element._type) {
				case MissionElementType.SimGroup:
					this.addSimGroup(cast element);
				case MissionElementType.InteriorInstance:
					resourceLoadFuncs.push(fwd -> this.addInteriorFromMis(cast element, fwd));
				case MissionElementType.StaticShape:
					resourceLoadFuncs.push(fwd -> this.addStaticShape(cast element, fwd));
				case MissionElementType.Item:
					resourceLoadFuncs.push(fwd -> this.addItem(cast element, fwd));
				case MissionElementType.Trigger:
					resourceLoadFuncs.push(fwd -> this.addTrigger(cast element, fwd));
				case MissionElementType.TSStatic:
					resourceLoadFuncs.push(fwd -> this.addTSStatic(cast element, fwd));
				case MissionElementType.ParticleEmitterNode:
					resourceLoadFuncs.push(fwd -> {
						this.addParticleEmitterNode(cast element);
						fwd();
					});
				default:
			}
		}
	}

	public function addInteriorFromMis(element:MissionElementInteriorInstance, onFinish:Void->Void) {
		var difPath = this.mission.getDifPath(element.interiorfile);
		if (difPath == "") {
			onFinish();
			return;
		}

		var interior = new InteriorObject();
		interior.interiorFile = difPath;
		// DifBuilder.loadDif(difPath, interior);
		// this.interiors.push(interior);
		this.addInterior(interior, () -> {
			var interiorPosition = MisParser.parseVector3(element.position);
			interiorPosition.x = -interiorPosition.x;
			var interiorRotation = MisParser.parseRotation(element.rotation);
			interiorRotation.x = -interiorRotation.x;
			interiorRotation.w = -interiorRotation.w;
			var interiorScale = MisParser.parseVector3(element.scale);
			var hasCollision = interiorScale.x * interiorScale.y * interiorScale.z != 0; // Don't want to add buggy geometry

			// Fix zero-volume interiors so they receive correct lighting
			if (interiorScale.x == 0)
				interiorScale.x = 0.0001;
			if (interiorScale.y == 0)
				interiorScale.y = 0.0001;
			if (interiorScale.z == 0)
				interiorScale.z = 0.0001;

			var mat = new Matrix();
			interiorRotation.toMatrix(mat);
			mat.scale(interiorScale.x, interiorScale.y, interiorScale.z);
			mat.setPosition(interiorPosition);

			interior.setTransform(mat);
			interior.isCollideable = hasCollision;
			onFinish();
		});

		// interior.setTransform(interiorPosition, interiorRotation, interiorScale);

		// this.scene.add(interior.group);
		// if (hasCollision)
		// 	this.physics.addInterior(interior);
	}

	public function addStaticShape(element:MissionElementStaticShape, onFinish:Void->Void) {
		var shape:DtsObject = null;

		// Add the correct shape based on type
		var dataBlockLowerCase = element.datablock.toLowerCase();
		if (dataBlockLowerCase == "") {} // Make sure we don't do anything if there's no data block
		else if (dataBlockLowerCase == "startpad")
			shape = new StartPad();
		else if (dataBlockLowerCase == "endpad") {
			shape = new EndPad();
			if (element == endPadElement)
				endPad = cast shape;
		} else if (dataBlockLowerCase == "signfinish")
			shape = new SignFinish();
		else if (StringTools.startsWith(dataBlockLowerCase, "signplain"))
			shape = new SignPlain(element);
		else if (StringTools.startsWith(dataBlockLowerCase, "gemitem")) {
			shape = new Gem(cast element);
			this.totalGems++;
			this.gems.push(cast shape);
		} else if (dataBlockLowerCase == "superjumpitem")
			shape = new SuperJump(cast element);
		else if (StringTools.startsWith(dataBlockLowerCase, "signcaution"))
			shape = new SignCaution(element);
		else if (dataBlockLowerCase == "superbounceitem")
			shape = new SuperBounce(cast element);
		else if (dataBlockLowerCase == "roundbumper")
			shape = new RoundBumper();
		else if (dataBlockLowerCase == "trianglebumper")
			shape = new TriangleBumper();
		else if (dataBlockLowerCase == "helicopteritem")
			shape = new Helicopter(cast element);
		else if (dataBlockLowerCase == "easteregg")
			shape = new EasterEgg(cast element);
		else if (dataBlockLowerCase == "checkpoint")
			shape = new Checkpoint(cast element);
		else if (dataBlockLowerCase == "ductfan")
			shape = new DuctFan();
		else if (dataBlockLowerCase == "smallductfan")
			shape = new SmallDuctFan();
		else if (dataBlockLowerCase == "magnet")
			shape = new Magnet();
		else if (dataBlockLowerCase == "antigravityitem")
			shape = new AntiGravity(cast element);
		else if (dataBlockLowerCase == "norespawnantigravityitem")
			shape = new AntiGravity(cast element, true);
		else if (dataBlockLowerCase == "landmine")
			shape = new LandMine();
		else if (dataBlockLowerCase == "nuke")
			shape = new Nuke();
		else if (dataBlockLowerCase == "shockabsorberitem")
			shape = new ShockAbsorber(cast element);
		else if (dataBlockLowerCase == "superspeeditem")
			shape = new SuperSpeed(cast element);
		else if (dataBlockLowerCase == "timetravelitem" || dataBlockLowerCase == "timepenaltyitem")
			shape = new TimeTravel(cast element);
		else if (dataBlockLowerCase == "blast")
			shape = new Blast(cast element);
		else if (dataBlockLowerCase == "megamarble")
			shape = new MegaMarble(cast element);
		else if (dataBlockLowerCase == "tornado")
			shape = new Tornado();
		else if (dataBlockLowerCase == "trapdoor")
			shape = new Trapdoor();
		else if (dataBlockLowerCase == "oilslick")
			shape = new Oilslick();
		else if (dataBlockLowerCase == "arrow" || StringTools.startsWith(dataBlockLowerCase, "sign"))
			shape = new Sign(cast element);
		else if ([
			"glass_3shape",
			"glass_6shape",
			"glass_9shape",
			"glass_12shape",
			"glass_15shape",
			"glass_18shape"
		].contains(dataBlockLowerCase))
			shape = new Glass(cast element);
		else if (["clear", "cloudy", "dusk", "wintry"].contains(dataBlockLowerCase))
			shape = new shapes.Sky(dataBlockLowerCase);
		else {
			Console.error("Unable to create static shape with data block '" + element.datablock + "'");
			onFinish();
			return;
		}

		if (element._name != null && element._name != "") {
			this.namedObjects.set(element._name, {
				obj: shape,
				elem: element
			});
		}

		var shapePosition = MisParser.parseVector3(element.position);
		shapePosition.x = -shapePosition.x;
		var shapeRotation = MisParser.parseRotation(element.rotation);
		shapeRotation.x = -shapeRotation.x;
		shapeRotation.w = -shapeRotation.w;
		var shapeScale = MisParser.parseVector3(element.scale);

		// Apparently we still do collide with zero-volume shapes
		if (shapeScale.x == 0)
			shapeScale.x = 0.0001;
		if (shapeScale.y == 0)
			shapeScale.y = 0.0001;
		if (shapeScale.z == 0)
			shapeScale.z = 0.0001;

		var mat = shapeRotation.toMatrix();
		mat.scale(shapeScale.x, shapeScale.y, shapeScale.z);
		mat.setPosition(shapePosition);

		this.addDtsObject(shape, () -> {
			shape.setTransform(mat);
			onFinish();
		});

		// else if (dataBlockLowerCase == "pushbutton")
		// 	shape = new PushButton();
	}

	public function addItem(element:MissionElementItem, onFinish:Void->Void) {
		var shape:DtsObject = null;

		// Add the correct shape based on type
		var dataBlockLowerCase = element.datablock.toLowerCase();
		if (dataBlockLowerCase == "") {} // Make sure we don't do anything if there's no data block
		else if (dataBlockLowerCase == "startpad")
			shape = new StartPad();
		else if (dataBlockLowerCase == "endpad")
			shape = new EndPad();
		else if (dataBlockLowerCase == "signfinish")
			shape = new SignFinish();
		else if (StringTools.startsWith(dataBlockLowerCase, "gemitem")) {
			shape = new Gem(cast element);
			this.totalGems++;
			this.gems.push(cast shape);
		} else if (dataBlockLowerCase == "superjumpitem")
			shape = new SuperJump(cast element);
		else if (dataBlockLowerCase == "superbounceitem")
			shape = new SuperBounce(cast element);
		else if (dataBlockLowerCase == "roundbumper")
			shape = new RoundBumper();
		else if (dataBlockLowerCase == "trianglebumper")
			shape = new TriangleBumper();
		else if (dataBlockLowerCase == "helicopteritem")
			shape = new Helicopter(cast element);
		else if (dataBlockLowerCase == "easteregg")
			shape = new EasterEgg(cast element);
		else if (dataBlockLowerCase == "checkpoint")
			shape = new Checkpoint(cast element);
		else if (dataBlockLowerCase == "ductfan")
			shape = new DuctFan();
		else if (dataBlockLowerCase == "smallductfan")
			shape = new SmallDuctFan();
		else if (dataBlockLowerCase == "magnet")
			shape = new Magnet();
		else if (dataBlockLowerCase == "antigravityitem")
			shape = new AntiGravity(cast element);
		else if (dataBlockLowerCase == "norespawnantigravityitem")
			shape = new AntiGravity(cast element, true);
		else if (dataBlockLowerCase == "landmine")
			shape = new LandMine();
		else if (dataBlockLowerCase == "nuke")
			shape = new Nuke();
		else if (dataBlockLowerCase == "shockabsorberitem")
			shape = new ShockAbsorber(cast element);
		else if (dataBlockLowerCase == "superspeeditem")
			shape = new SuperSpeed(cast element);
		else if (dataBlockLowerCase == "timetravelitem" || dataBlockLowerCase == "timepenaltyitem")
			shape = new TimeTravel(cast element);
		else if (dataBlockLowerCase == "blastitem")
			shape = new Blast(cast element);
		else if (dataBlockLowerCase == "megamarbleitem")
			shape = new MegaMarble(cast element);
		else if (dataBlockLowerCase == "tornado")
			shape = new Tornado();
		else if (dataBlockLowerCase == "trapdoor")
			shape = new Trapdoor();
		else if (dataBlockLowerCase == "oilslick")
			shape = new Oilslick();
		else if (dataBlockLowerCase == "arrow" || StringTools.startsWith(dataBlockLowerCase, "sign"))
			shape = new Sign(cast element);
		else if ([
			"glass_3shape",
			"glass_6shape",
			"glass_9shape",
			"glass_12shape",
			"glass_15shape",
			"glass_18shape"
		].contains(dataBlockLowerCase))
			shape = new Glass(cast element);
		else if (["clear", "cloudy", "dusk", "wintry"].contains(dataBlockLowerCase))
			shape = new shapes.Sky(dataBlockLowerCase);
		else {
			Console.error("Unknown item: " + element.datablock);
			onFinish();
			return;
		}

		if (element._name != null && element._name != "") {
			this.namedObjects.set(element._name, {
				obj: shape,
				elem: element
			});
		}

		var shapePosition = MisParser.parseVector3(element.position);
		shapePosition.x = -shapePosition.x;
		var shapeRotation = MisParser.parseRotation(element.rotation);
		shapeRotation.x = -shapeRotation.x;
		shapeRotation.w = -shapeRotation.w;
		var shapeScale = MisParser.parseVector3(element.scale);

		// Apparently we still do collide with zero-volume shapes
		if (shapeScale.x == 0)
			shapeScale.x = 0.0001;
		if (shapeScale.y == 0)
			shapeScale.y = 0.0001;
		if (shapeScale.z == 0)
			shapeScale.z = 0.0001;

		var mat = shapeRotation.toMatrix();
		mat.scale(shapeScale.x, shapeScale.y, shapeScale.z);
		mat.setPosition(shapePosition);

		this.addDtsObject(shape, () -> {
			shape.setTransform(mat);
			onFinish();
		});
	}

	public function addTrigger(element:MissionElementTrigger, onFinish:Void->Void) {
		var trigger:Trigger = null;

		var datablockLowercase = element.datablock.toLowerCase();

		// Create a trigger based on type
		if (datablockLowercase == "outofboundstrigger") {
			trigger = new OutOfBoundsTrigger(element, cast this);
		} else if (datablockLowercase == "inboundstrigger") {
			trigger = new InBoundsTrigger(element, cast this);
		} else if (datablockLowercase == "helptrigger") {
			trigger = new HelpTrigger(element, cast this);
		} else if (datablockLowercase == "teleporttrigger") {
			trigger = new TeleportTrigger(element, cast this);
		} else if (datablockLowercase == "destinationtrigger") {
			trigger = new DestinationTrigger(element, cast this);
		} else if (datablockLowercase == "checkpointtrigger") {
			trigger = new CheckpointTrigger(element, cast this);
		} else {
			Console.error("Unknown trigger: " + element.datablock);
			onFinish();
			return;
		}

		trigger.init(() -> {
			this.triggers.push(trigger);
			this.collisionWorld.addEntity(trigger.collider);
			onFinish();
		});
	}

	public function addTSStatic(element:MissionElementTSStatic, onFinish:Void->Void) {
		// !! WARNING - UNTESTED !!
		var shapeName = element.shapename;
		var index = shapeName.indexOf('data/');
		if (index == -1) {
			Console.error("Unable to parse shape path: " + shapeName);
			onFinish();
			return;
		}

		var dtsPath = 'data/' + shapeName.substring(index + 'data/'.length);
		if (ResourceLoader.getProperFilepath(dtsPath) == "") {
			Console.error("DTS path does not exist: " + dtsPath);
			onFinish();
			return;
		}

		var tsShape = new DtsObject();
		tsShape.useInstancing = true;
		tsShape.dtsPath = dtsPath;
		tsShape.identifier = shapeName;
		tsShape.isCollideable = true;

		if (element._name != null && element._name != "") {
			this.namedObjects.set(element._name, {
				obj: tsShape,
				elem: element
			});
		}

		var shapePosition = MisParser.parseVector3(element.position);
		shapePosition.x = -shapePosition.x;
		var shapeRotation = MisParser.parseRotation(element.rotation);
		shapeRotation.x = -shapeRotation.x;
		shapeRotation.w = -shapeRotation.w;
		var shapeScale = MisParser.parseVector3(element.scale);

		// Apparently we still do collide with zero-volume shapes
		if (shapeScale.x == 0)
			shapeScale.x = 0.0001;
		if (shapeScale.y == 0)
			shapeScale.y = 0.0001;
		if (shapeScale.z == 0)
			shapeScale.z = 0.0001;

		var mat = shapeRotation.toMatrix();
		mat.scale(shapeScale.x, shapeScale.y, shapeScale.z);
		mat.setPosition(shapePosition);

		this.addDtsObject(tsShape, () -> {
			tsShape.setTransform(mat);
			onFinish();
		});
	}

	public function addParticleEmitterNode(element:MissionElementParticleEmitterNode) {
		Console.warn("Unimplemented method addParticleEmitterNode");
		// TODO THIS SHIT
	}

	public function addInterior(obj:InteriorObject, onFinish:Void->Void) {
		this.interiors.push(obj);
		obj.init(cast this, () -> {
			this.collisionWorld.addEntity(obj.collider);
			if (obj.useInstancing)
				this.instanceManager.addObject(obj);
			else
				this.scene.addChild(obj);
			onFinish();
		});
	}

	public function addPathedInterior(obj:PathedInterior, onFinish:Void->Void) {
		this.pathedInteriors.push(obj);
		obj.init(cast this, () -> {
			this.collisionWorld.addMovingEntity(obj.collider);
			if (obj.useInstancing)
				this.instanceManager.addObject(obj);
			else
				this.scene.addChild(obj);
			onFinish();
		});
	}

	public function addDtsObject(obj:DtsObject, onFinish:Void->Void) {
		function parseIfl(path:String, onFinish:Array<String>->Void) {
			ResourceLoader.load(path).entry.load(() -> {
				var text = ResourceLoader.fileSystem.get(path).getText();
				var lines = text.split('\n');
				var keyframes = [];
				for (line in lines) {
					line = StringTools.trim(line);
					if (line.substr(0, 2) == "//")
						continue;
					if (line == "")
						continue;

					var parts = line.split(' ');
					var count = parts.length > 1 ? Std.parseInt(parts[1]) : 1;

					for (i in 0...count) {
						keyframes.push(parts[0]);
					}
				}

				onFinish(keyframes);
			});
		}

		ResourceLoader.load(obj.dtsPath).entry.load(() -> {
			var dtsFile = ResourceLoader.loadDts(obj.dtsPath);
			var directoryPath = haxe.io.Path.directory(obj.dtsPath);
			var texToLoad = [];
			for (i in 0...dtsFile.resource.matNames.length) {
				var matName = obj.matNameOverride.exists(dtsFile.resource.matNames[i]) ? obj.matNameOverride.get(dtsFile.resource.matNames[i]) : dtsFile.resource.matNames[i];
				var fullNames = ResourceLoader.getFullNamesOf(directoryPath + '/' + matName).filter(x -> haxe.io.Path.extension(x) != "dts");
				var fullName = fullNames.length > 0 ? fullNames[0] : null;
				if (fullName != null) {
					texToLoad.push(fullName);
				}
			}

			var worker = new ResourceLoaderWorker(() -> {
				obj.idInLevel = this.dtsObjects.length; // Set the id of the thing
				this.dtsObjects.push(obj);
				if (obj is ForceObject) {
					this.forceObjects.push(cast obj);
				}
				obj.init(cast this, () -> {
					obj.update(this.timeState);
					if (obj.useInstancing) {
						this.instanceManager.addObject(obj);
					} else
						this.scene.addChild(obj);
					for (collider in obj.colliders) {
						if (collider != null)
							this.collisionWorld.addEntity(collider);
					}
					if (obj.isBoundingBoxCollideable)
						this.collisionWorld.addEntity(obj.boundingCollider);

					onFinish();
				});
			});

			for (texPath in texToLoad) {
				if (haxe.io.Path.extension(texPath) == "ifl") {
					worker.addTask(fwd -> {
						parseIfl(texPath, keyframes -> {
							var innerWorker = new ResourceLoaderWorker(() -> {
								fwd();
							});
							var loadedkf = [];
							for (kf in keyframes) {
								if (!loadedkf.contains(kf)) {
									innerWorker.loadFile(directoryPath + '/' + kf);
									loadedkf.push(kf);
								}
							}
							innerWorker.run();
						});
					});
				} else {
					worker.loadFile(texPath);
				}
			}

			worker.run();
		});
	}

	public function addMarble(marble:Marble, onFinish:Void->Void) {
		this.marbles.push(marble);
		marble.level = cast this;
		if (marble.controllable) {
			marble.init(cast this, () -> {
				this.scene.addChild(marble.camera);
				this.marble = marble;
				// Ugly hack
				// sky.follow = marble;
				sky.follow = marble.camera;
				this.collisionWorld.addMovingEntity(marble.collider);
				this.scene.addChild(marble);
				onFinish();
			});
		} else {
			this.collisionWorld.addMovingEntity(marble.collider);
			this.scene.addChild(marble);
		}
	}

	public function performRestart() {
		this.respawnPressedTime = timeState.timeSinceLoad;
		this.restart();
		if (!this.isWatching) {
			Settings.playStatistics.respawns++;

			if (!Settings.levelStatistics.exists(mission.path)) {
				Settings.levelStatistics.set(mission.path, {
					oobs: 0,
					respawns: 1,
					totalTime: 0,
				});
			} else {
				Settings.levelStatistics[mission.path].respawns++;
			}
		}
	}

	public function update(dt:Float) {
		if (!_ready) {
			return;
		}
		if (!this.isWatching) {
			if (this.isRecording) {
				this.replay.startFrame();
			}
		} else {
			if (!this.replay.advance(dt)) {
				if (Util.isTouchDevice()) {
					MarbleGame.instance.touchInput.hideControls(@:privateAccess this.playGui.playGuiCtrl);
				}
				this.setCursorLock(false);
				this.dispose();
				#if !js
				MarbleGame.canvas.setContent(new ReplayCenterGui());
				#end
				#if js
				MarbleGame.canvas.setContent(new MainMenuGui());
				var pointercontainer = js.Browser.document.querySelector("#pointercontainer");
				pointercontainer.hidden = false;
				#end
				return;
			}
		}

		ProfilerUI.measure("updateTimer");
		this.updateTimer(dt);

		if ((Key.isPressed(Settings.controlsSettings.respawn) || Gamepad.isPressed(Settings.gamepadSettings.respawn))
			&& this.finishTime == null) {
			performRestart();
			return;
		}

		if ((Key.isDown(Settings.controlsSettings.respawn)
			|| MarbleGame.instance.touchInput.restartButton.pressed
			|| Gamepad.isDown(Settings.gamepadSettings.respawn))
			&& !this.isWatching
			&& this.finishTime == null) {
			if (timeState.timeSinceLoad - this.respawnPressedTime > 1.5) {
				this.restart(true);
				this.respawnPressedTime = Math.POSITIVE_INFINITY;
				return;
			}
		}

		this.tickSchedule(timeState.currentAttemptTime);

		if (Key.isPressed(Settings.controlsSettings.blast)
			|| (MarbleGame.instance.touchInput.blastbutton.pressed)
			|| Gamepad.isPressed(Settings.gamepadSettings.blast)
			&& !this.isWatching
			&& this.game == "ultra") {
			this.marble.useBlast();
			if (this.isRecording) {
				this.replay.recordMarbleStateFlags(false, false, false, true);
			}
		}

		if (this.isWatching && this.replay.currentPlaybackFrame.marbleStateFlags.has(UsedBlast))
			this.marble.useBlast();

		// Replay gravity
		if (this.isWatching) {
			if (this.replay.currentPlaybackFrame.gravityChange) {
				this.setUp(this.replay.currentPlaybackFrame.gravity, timeState, this.replay.currentPlaybackFrame.gravityInstant);
			}
			if (this.replay.currentPlaybackFrame.powerupPickup != null) {
				this.pickUpPowerUpReplay(this.replay.currentPlaybackFrame.powerupPickup);
			}
		}

		this.updateGameState();
		this.updateBlast(timeState);
		ProfilerUI.measure("updateDTS");
		for (obj in dtsObjects) {
			obj.update(timeState);
		}
		for (obj in triggers) {
			obj.update(timeState);
		}
		ProfilerUI.measure("updateMarbles");
		for (marble in marbles) {
			marble.update(timeState, collisionWorld, this.pathedInteriors);
		}
		ProfilerUI.measure("updateInstances");
		this.instanceManager.render();
		ProfilerUI.measure("updateParticles");
		this.particleManager.update(1000 * timeState.timeSinceLoad, dt);
		ProfilerUI.measure("updatePlayGui");
		this.playGui.update(timeState);
		ProfilerUI.measure("updateAudio");
		AudioManager.update(this.scene);

		if (this.outOfBounds
			&& this.finishTime == null
			&& (Key.isDown(Settings.controlsSettings.powerup) || Gamepad.isDown(Settings.gamepadSettings.powerup))
			&& !this.isWatching) {
			this.restart();
			return;
		}

		if (!this.isWatching) {
			if (this.isRecording) {
				this.replay.endFrame();
			}
		}

		this.updateTexts();
	}

	public function render(e:h3d.Engine) {
		if (!_ready)
			asyncLoadResources();
		if (this.playGui != null && _ready)
			this.playGui.render(e);
		if (this.marble != null && this.marble.cubemapRenderer != null) {
			this.marble.cubemapRenderer.position.load(this.marble.getAbsPos().getPosition());
			this.marble.cubemapRenderer.render(e, 0.002);
		}
	}

	var postInited = false;

	function asyncLoadResources() {
		if (this.resourceLoadFuncs.length != 0) {
			if (lock)
				return;

			var func = this.resourceLoadFuncs.shift();
			lock = true;
			#if hl
			func(() -> {
				lock = false;
				this._resourcesLoaded++;
				this.loadingGui.setProgress((1 - resourceLoadFuncs.length / _loadingLength));
			});
			#end
			#if js
			func(() -> {
				lock = false;
				this.loadingGui.setProgress((1 - resourceLoadFuncs.length / _loadingLength));
				this._resourcesLoaded++;
			});
			#end
		} else {
			if (this._resourcesLoaded < _loadingLength)
				return;
			if (!_ready && !postInited) {
				postInited = true;
				Console.log("Finished loading, starting mission");
				postInit();
			}
		}
	}

	function determineClockColor(timeToDisplay:Float) {
		if (this.finishTime != null)
			return 1;
		if (this.timeState.currentAttemptTime < 3.5 || this.bonusTime > 0)
			return 1;
		if (timeToDisplay >= this.mission.qualifyTime)
			return 2;

		if (this.timeState.currentAttemptTime >= 3.5) {
			// Create the flashing effect
			var alarmStart = this.mission.computeAlarmStartTime();
			var elapsed = timeToDisplay - alarmStart;
			if (elapsed < 0)
				return 0;
			if (Math.floor(elapsed) % 2 == 0)
				return 2;
		}

		return 0; // Default yellow
	}

	public function updateTimer(dt:Float) {
		this.timeState.dt = dt;

		var prevGameplayClock = this.timeState.gameplayClock;

		if (!this.isWatching) {
			if (this.bonusTime != 0 && this.timeState.currentAttemptTime >= 3.5) {
				this.bonusTime -= dt;
				if (this.bonusTime < 0) {
					this.timeState.gameplayClock -= this.bonusTime;
					this.bonusTime = 0;
				}
				if (timeTravelSound == null) {
					var ttsnd = ResourceLoader.getResource("data/sound/timetravelactive.wav", ResourceLoader.getAudio, this.soundResources);
					timeTravelSound = AudioManager.playSound(ttsnd, null, true);

					if (alarmSound != null)
						alarmSound.pause = true;
				}
			} else {
				if (timeTravelSound != null) {
					timeTravelSound.stop();
					timeTravelSound = null;
					if (alarmSound != null)
						alarmSound.pause = false;
				}
				if (this.timeState.currentAttemptTime >= 3.5) {
					this.timeState.gameplayClock += dt;
				} else if (this.timeState.currentAttemptTime + dt >= 3.5) {
					this.timeState.gameplayClock += (this.timeState.currentAttemptTime + dt) - 3.5;
				}
			}
			this.timeState.currentAttemptTime += dt;
		} else {
			this.timeState.currentAttemptTime = this.replay.currentPlaybackFrame.time;
			this.timeState.gameplayClock = this.replay.currentPlaybackFrame.clockTime;
			this.bonusTime = this.replay.currentPlaybackFrame.bonusTime;
			if (this.bonusTime != 0 && this.timeState.currentAttemptTime >= 3.5) {
				if (timeTravelSound == null) {
					var ttsnd = ResourceLoader.getResource("data/sound/timetravelactive.wav", ResourceLoader.getAudio, this.soundResources);
					timeTravelSound = AudioManager.playSound(ttsnd, null, true);
				}
			} else {
				if (timeTravelSound != null) {
					timeTravelSound.stop();
					timeTravelSound = null;
				}
			}
		}
		this.timeState.timeSinceLoad += dt;

		// Handle alarm warnings (that the user is about to exceed the par time)
		if (this.timeState.currentAttemptTime >= 3.5) {
			var alarmStart = this.mission.computeAlarmStartTime();

			if (prevGameplayClock < alarmStart && this.timeState.gameplayClock >= alarmStart) {
				// Start the alarm
				this.alarmSound = AudioManager.playSound(ResourceLoader.getResource("data/sound/alarm.wav", ResourceLoader.getAudio, this.soundResources),
					null, true); // AudioManager.createAudioSource('alarm.wav');
				this.displayHelp('You have ${(this.mission.qualifyTime - alarmStart)} seconds remaining.');
			}
			if (prevGameplayClock < this.mission.qualifyTime && this.timeState.gameplayClock >= this.mission.qualifyTime) {
				// Stop the alarm
				if (this.alarmSound != null) {
					this.alarmSound.stop();
					this.alarmSound = null;
				}
				this.displayHelp("The clock has passed the Par Time.");
				AudioManager.playSound(ResourceLoader.getResource("data/sound/alarm_timeout.wav", ResourceLoader.getAudio, this.soundResources));
			}
		}

		if (finishTime != null)
			this.timeState.gameplayClock = finishTime.gameplayClock;
		playGui.formatTimer(this.timeState.gameplayClock, determineClockColor(this.timeState.gameplayClock));

		if (!this.isWatching && this.isRecording)
			this.replay.recordTimeState(timeState.currentAttemptTime, timeState.gameplayClock, this.bonusTime);
	}

	function updateBlast(timestate:TimeState) {
		if (this.game == "ultra") {
			if (this.blastAmount < 1) {
				this.blastAmount = Util.clamp(this.blastAmount + (timeState.dt / 25), 0, 1);
			}
			this.playGui.setBlastValue(this.blastAmount);
		}
	}

	function updateTexts() {
		var helpTextTime = this.helpTextTimeState;
		var alertTextTime = this.alertTextTimeState;
		var helpTextCompletion = Math.pow(Util.clamp((this.timeState.timeSinceLoad - helpTextTime - 3), 0, 1), 2);
		var alertTextCompletion = Math.pow(Util.clamp((this.timeState.timeSinceLoad - alertTextTime - 3), 0, 1), 2);
		this.playGui.setHelpTextOpacity(1 - helpTextCompletion);
		this.playGui.setAlertTextOpacity(1 - alertTextCompletion);
	}

	public function displayAlert(text:String) {
		this.playGui.setAlertText(text);
		this.alertTextTimeState = this.timeState.timeSinceLoad;
	}

	public function displayHelp(text:String) {
		var start = 0;
		var pos = text.indexOf("<func:", start);
		while (pos != -1) {
			var end = text.indexOf(">", start + 5);
			if (end == -1)
				break;
			var pre = text.substr(0, pos);
			var post = text.substr(end + 1);
			var func = text.substr(pos + 6, end - (pos + 6));
			var funcdata = func.split(' ').map(x -> x.toLowerCase());
			var val = "";
			if (funcdata[0] == "bind") {
				if (funcdata[1] == "moveforward")
					val = Util.getKeyForButton(Settings.controlsSettings.forward);
				if (funcdata[1] == "movebackward")
					val = Util.getKeyForButton(Settings.controlsSettings.backward);
				if (funcdata[1] == "moveleft")
					val = Util.getKeyForButton(Settings.controlsSettings.left);
				if (funcdata[1] == "moveright")
					val = Util.getKeyForButton(Settings.controlsSettings.right);
				if (funcdata[1] == "panup")
					val = Util.getKeyForButton(Settings.controlsSettings.camForward);
				if (funcdata[1] == "pandown")
					val = Util.getKeyForButton(Settings.controlsSettings.camBackward);
				if (funcdata[1] == "turnleft")
					val = Util.getKeyForButton(Settings.controlsSettings.camLeft);
				if (funcdata[1] == "turnright")
					val = Util.getKeyForButton(Settings.controlsSettings.camRight);
				if (funcdata[1] == "jump")
					val = Util.getKeyForButton(Settings.controlsSettings.jump);
				if (funcdata[1] == "mousefire")
					val = Util.getKeyForButton(Settings.controlsSettings.powerup);
				if (funcdata[1] == "freelook")
					val = Util.getKeyForButton(Settings.controlsSettings.freelook);
				if (funcdata[1] == "useblast")
					val = Util.getKeyForButton(Settings.controlsSettings.blast);
			}
			start = val.length + pos;
			text = pre + val + post;
			pos = text.indexOf("<func:", start);
		}
		this.playGui.setHelpText(text);
		this.helpTextTimeState = this.timeState.timeSinceLoad;
	}

	public function pickUpGem(gem:Gem) {
		this.gemCount++;
		var string:String;

		// Show a notification (and play a sound) based on the gems remaining
		if (this.gemCount == this.totalGems) {
			string = "You have all the diamonds, head for the finish!";
			// if (!this.rewinding)
			AudioManager.playSound(ResourceLoader.getResource('data/sound/gotallgems.wav', ResourceLoader.getAudio, this.soundResources));

			// Some levels with this package end immediately upon collection of all gems
			// if (this.mission.misFile.activatedPackages.includes('endWithTheGems')) {
			// 	let
			// 	completionOfImpact = this.physics.computeCompletionOfImpactWithBody(gem.bodies[0], 2); // Get the exact point of impact
			// 	this.touchFinish(completionOfImpact);
			// }
		} else {
			string = "You picked up a diamond.  ";

			var remaining = this.totalGems - this.gemCount;
			if (remaining == 1) {
				string += "Only one diamond to go!";
			} else {
				string += '${remaining} diamonds to go!';
			}

			// if (!this.rewinding)
			AudioManager.playSound(ResourceLoader.getResource('data/sound/gotgem.wav', ResourceLoader.getAudio, this.soundResources));
		}

		displayAlert(string);
		this.playGui.formatGemCounter(this.gemCount, this.totalGems);
	}

	public function callCollisionHandlers(marble:Marble, timeState:TimeState, start:Vector, end:Vector, startQuat:Quat, endQuat:Quat) {
		var expansion = marble._radius + 0.2;
		var minP = new Vector(Math.min(start.x, end.x) - expansion, Math.min(start.y, end.y) - expansion, Math.min(start.z, end.z) - expansion);
		var maxP = new Vector(Math.max(start.x, end.x) + expansion, Math.max(start.y, end.y) + expansion, Math.max(start.z, end.z) + expansion);
		var box = Bounds.fromPoints(minP.toPoint(), maxP.toPoint());

		var marbleHitbox = new Bounds();
		marbleHitbox.addSpherePos(0, 0, 0, marble._radius);
		marbleHitbox.transform(startQuat.toMatrix());
		marbleHitbox.transform(endQuat.toMatrix());
		marbleHitbox.offset(end.x, end.y, end.z);

		// spherebounds.addSpherePos(gjkCapsule.p2.x, gjkCapsule.p2.y, gjkCapsule.p2.z, gjkCapsule.radius);
		// var contacts = this.collisionWorld.radiusSearch(marble.getAbsPos().getPosition(), marble._radius);
		var contacts = marble.contactEntities;
		var inside = [];

		for (contact in contacts) {
			if (contact.go != marble) {
				if (contact.go is DtsObject) {
					var shape:DtsObject = cast contact.go;

					if (contact.boundingBox.collide(marbleHitbox)) {
						shape.onMarbleInside(timeState);
						if (!this.shapeOrTriggerInside.contains(contact.go)) {
							this.shapeOrTriggerInside.push(contact.go);
							shape.onMarbleEnter(timeState);
						}
						inside.push(contact.go);
					}
				}
				if (contact.go is Trigger) {
					var trigger:Trigger = cast contact.go;
					var triggeraabb = trigger.collider.boundingBox;

					if (triggeraabb.collide(marbleHitbox)) {
						trigger.onMarbleInside(timeState);
						if (!this.shapeOrTriggerInside.contains(contact.go)) {
							this.shapeOrTriggerInside.push(contact.go);
							trigger.onMarbleEnter(timeState);
						}
						inside.push(contact.go);
					}
				}
			}
		}

		for (object in shapeOrTriggerInside) {
			if (!inside.contains(object)) {
				this.shapeOrTriggerInside.remove(object);
				object.onMarbleLeave(timeState);
			}
		}

		if (this.finishTime == null) {
			if (marbleHitbox.collide(this.endPad.finishBounds)) {
				var padUp = this.endPad.getAbsPos().up();
				padUp = padUp.multiply(10);

				var checkBounds = box.clone();
				checkBounds.zMin -= 10;
				checkBounds.zMax += 10;
				var checkBoundsCenter = checkBounds.getCenter();
				var checkSphereRadius = checkBounds.getMax().sub(checkBoundsCenter).length();
				var checkSphere = new Bounds();
				checkSphere.addSpherePos(checkBoundsCenter.x, checkBoundsCenter.y, checkBoundsCenter.z, checkSphereRadius);
				var endpadBB = this.collisionWorld.boundingSearch(checkSphere, false);
				var found = false;
				for (collider in endpadBB) {
					if (collider.go == this.endPad) {
						var chull = cast(collider, collision.CollisionHull);
						for (surface in chull.surfaces) {
							var i = 0;
							while (i < surface.indices.length) {
								var surfaceN = surface.normals[surface.indices[i]].transformed3x3(chull.transform);
								var v1 = surface.points[surface.indices[i]].transformed(chull.transform);
								var surfaceD = -surfaceN.dot(v1);

								if (surfaceN.dot(padUp.multiply(-10)) < 0) {
									var dist = surfaceN.dot(checkBoundsCenter.toVector()) + surfaceD;
									if (dist >= 0 && dist < 5) {
										var intersectT = -(checkBoundsCenter.dot(surfaceN.toPoint()) + surfaceD) / (padUp.dot(surfaceN));
										var intersectP = checkBoundsCenter.add(padUp.multiply(intersectT).toPoint()).toVector();
										if (Collision.PointInTriangle(intersectP, v1, surface.points[surface.indices[i + 1]].transformed(chull.transform),
											surface.points[surface.indices[i + 2]].transformed(chull.transform))) {
											found = true;
											break;
										}
									}
								}

								i += 3;
							}

							if (found) {
								break;
							}
						}
						if (found) {
							break;
						}
					}
				}
				if (found) {
					if (!endPad.inFinish) {
						touchFinish();
						endPad.inFinish = true;
					}
				} else {
					if (endPad.inFinish)
						endPad.inFinish = false;
				}
			} else {
				if (endPad.inFinish)
					endPad.inFinish = false;
			}
		}
	}

	function touchFinish() {
		if (this.finishTime != null
			|| (this.outOfBounds && this.timeState.currentAttemptTime - this.outOfBoundsTime.currentAttemptTime >= 0.5))
			return;

		if (this.gemCount < this.totalGems) {
			AudioManager.playSound(ResourceLoader.getResource('data/sound/missinggems.wav', ResourceLoader.getAudio, this.soundResources));
			displayAlert("You can't finish without all the diamonds!!");
		} else {
			this.endPad.spawnFirework(this.timeState);
			this.finishTime = this.timeState.clone();
			this.marble.mode = Finish;
			this.marble.camera.finish = true;
			this.finishYaw = this.marble.camera.CameraYaw;
			this.finishPitch = this.marble.camera.CameraPitch;
			displayAlert("Congratulations! You've finished!");
			if (!this.isWatching)
				this.schedule(this.timeState.currentAttemptTime + 2, () -> cast showFinishScreen());
			// Stop the ongoing sounds
			if (timeTravelSound != null) {
				timeTravelSound.stop();
				timeTravelSound = null;
			}
			if (alarmSound != null) {
				alarmSound.stop();
				alarmSound = null;
			}
		}
	}

	function showFinishScreen() {
		if (this.isWatching)
			return 0;
		Console.log("State End");
		var egg:EndGameGui = null;
		#if js
		var pointercontainer = js.Browser.document.querySelector("#pointercontainer");
		pointercontainer.hidden = false;
		#end
		this.schedule(this.timeState.currentAttemptTime + 3, () -> {
			this.isRecording = false; // Stop recording here
		}, "stopRecordingTimeout");
		if (Util.isTouchDevice()) {
			MarbleGame.instance.touchInput.setControlsEnabled(false);
		}
		egg = new EndGameGui((sender) -> {
			if (Util.isTouchDevice()) {
				MarbleGame.instance.touchInput.hideControls(@:privateAccess this.playGui.playGuiCtrl);
			}
			var endGameCode = () -> {
				this.dispose();
				var pmg = new PlayMissionGui();
				PlayMissionGui.currentSelectionStatic = mission.index + 1;
				MarbleGame.canvas.setContent(pmg);
				#if js
				pointercontainer.hidden = false;
				#end
			}
			if (MarbleGame.instance.toRecord) {
				MarbleGame.canvas.pushDialog(new ReplayNameDlg(endGameCode));
			} else {
				endGameCode();
			}
		}, (sender) -> {
			var restartGameCode = () -> {
				MarbleGame.canvas.popDialog(egg);
				this.restart(true);
				#if js
				pointercontainer.hidden = true;
				#end
				if (Util.isTouchDevice()) {
					MarbleGame.instance.touchInput.setControlsEnabled(true);
				}
				// @:privateAccess playGui.playGuiCtrl.render(scene2d);
			}
			if (MarbleGame.instance.toRecord) {
				MarbleGame.canvas.pushDialog(new ReplayNameDlg(() -> {
					this.isRecording = true;
					restartGameCode();
				}));
			} else {
				restartGameCode();
			}
		}, (sender) -> {
			var nextLevelCode = () -> {
				var nextMission = mission.getNextMission();
				if (nextMission != null) {
					MarbleGame.instance.playMission(nextMission);
				}
			}
			if (MarbleGame.instance.toRecord) {
				MarbleGame.canvas.pushDialog(new ReplayNameDlg(nextLevelCode));
			} else {
				nextLevelCode();
			}
		}, mission, finishTime);
		MarbleGame.canvas.pushDialog(egg);
		this.setCursorLock(false);
		return 0;
	}

	public function pickUpPowerUpReplay(powerupIdent:String) {
		if (powerupIdent == null)
			return false;
		if (this.marble.heldPowerup != null)
			if (this.marble.heldPowerup.identifier == powerupIdent)
				return false;

		this.playGui.setPowerupImage(powerupIdent);

		return true;
	}

	public function pickUpPowerUp(powerUp:PowerUp) {
		if (powerUp == null)
			return false;
		if (this.marble.heldPowerup != null)
			if (this.marble.heldPowerup.identifier == powerUp.identifier)
				return false;
		Console.log("PowerUp pickup: " + powerUp.identifier);
		this.marble.heldPowerup = powerUp;
		this.playGui.setPowerupImage(powerUp.identifier);
		MarbleGame.instance.touchInput.powerupButton.setEnabled(true);
		if (this.isRecording) {
			this.replay.recordPowerupPickup(powerUp);
		}
		return true;
	}

	public function deselectPowerUp() {
		this.marble.heldPowerup = null;
		this.playGui.setPowerupImage("");
		MarbleGame.instance.touchInput.powerupButton.setEnabled(false);
	}

	public function addBonusTime(t:Float) {
		this.bonusTime += t;
		if (t > 0) {
			this.playGui.addMiddleMessage('-${t}s', 0x99ff99);
		} else if (t < 0) {
			this.playGui.addMiddleMessage('+${- t}s', 0xff9999);
		} else {
			this.playGui.addMiddleMessage('+0s', 0xcccccc);
		}
	}

	/** Get the current interpolated orientation quaternion. */
	public function getOrientationQuat(time:Float) {
		var completion = Util.clamp((time - this.orientationChangeTime) / 0.3, 0, 1);
		var q = this.oldOrientationQuat.clone();
		q.slerp(q, this.newOrientationQuat, completion);
		return q;
	}

	public function setUp(vec:Vector, timeState:TimeState, instant:Bool = false) {
		this.currentUp = vec;
		var currentQuat = this.getOrientationQuat(timeState.currentAttemptTime);
		var oldUp = new Vector(0, 0, 1);
		oldUp.transform(currentQuat.toMatrix());

		function getRotQuat(v1:Vector, v2:Vector) {
			function orthogonal(v:Vector) {
				var x = Math.abs(v.x);
				var y = Math.abs(v.y);
				var z = Math.abs(v.z);
				var other = x < y ? (x < z ? new Vector(1, 0, 0) : new Vector(0, 0, 1)) : (y < z ? new Vector(0, 1, 0) : new Vector(0, 0, 1));
				return v.cross(other);
			}

			var u = v1.normalized();
			var v = v2.normalized();
			if (u.dot(v) == -1) {
				var q = new Quat();
				var o = orthogonal(u).normalized();
				q.x = o.x;
				q.y = o.y;
				q.z = o.z;
				q.w = 0;
				return q;
			}
			var half = u.add(v).normalized();
			var q = new Quat();
			q.w = u.dot(half);
			var vr = u.cross(half);
			q.x = vr.x;
			q.y = vr.y;
			q.z = vr.z;
			return q;
		}

		var quatChange = getRotQuat(oldUp, vec);
		// Instead of calculating the new quat from nothing, calculate it from the last one to guarantee the shortest possible rotation.
		// quatChange.initMoveTo(oldUp, vec);
		quatChange.multiply(quatChange, currentQuat);

		if (this.isRecording) {
			this.replay.recordGravity(vec, instant);
		}

		this.newOrientationQuat = quatChange;
		this.oldOrientationQuat = currentQuat;
		this.orientationChangeTime = instant ? -1e8 : timeState.currentAttemptTime;
	}

	public function goOutOfBounds() {
		if (this.outOfBounds || this.finishTime != null)
			return;
		// this.updateCamera(this.timeState); // Update the camera at the point of OOB-ing
		this.outOfBounds = true;
		this.outOfBoundsTime = this.timeState.clone();
		this.marble.camera.oob = true;
		if (!this.isWatching) {
			Settings.playStatistics.oobs++;
			if (!Settings.levelStatistics.exists(mission.path)) {
				Settings.levelStatistics.set(mission.path, {
					oobs: 1,
					respawns: 0,
					totalTime: 0,
				});
			} else {
				Settings.levelStatistics[mission.path].oobs++;
			}
			if (Settings.optionsSettings.oobInsults)
				OOBInsultGui.OOBCheck();
		}
		// sky.follow = null;
		// this.oobCameraPosition = camera.position.clone();
		playGui.setCenterText('outofbounds');
		AudioManager.playSound(ResourceLoader.getResource('data/sound/whoosh.wav', ResourceLoader.getAudio, this.soundResources));
		// if (this.replay.mode != = 'playback')
		this.schedule(this.timeState.currentAttemptTime + 2, () -> {
			playGui.setCenterText('none');
			return null;
		});
		this.schedule(this.timeState.currentAttemptTime + 2.5, () -> {
			this.restart();
			return null;
		});
	}

	/** Sets a new active checkpoint. */
	public function saveCheckpointState(shape:{obj:DtsObject, elem:MissionElementBase}, trigger:CheckpointTrigger = null) {
		if (this.currentCheckpoint != null)
			if (this.currentCheckpoint.obj == shape.obj)
				return;
		var disableOob = false;
		if (shape != null) {
			if (shape.elem.fields.exists('disableOob')) {
				disableOob = MisParser.parseBoolean(shape.elem.fields.get('disableOob')[0]);
			}
		}
		if (trigger != null) {
			disableOob = trigger.disableOOB;
		}
		// (shape.srcElement as any) ?.disableOob || trigger?.element.disableOob;
		if (disableOob && this.outOfBounds)
			return; // The checkpoint is configured to not work when the player is already OOB
		this.currentCheckpoint = shape;
		this.currentCheckpointTrigger = trigger;
		this.checkpointCollectedGems.clear();
		this.checkpointUp = this.currentUp.clone();
		this.cheeckpointBlast = this.blastAmount;
		// Remember all gems that were collected up to this point
		for (gem in this.gems) {
			if (gem.pickedUp)
				this.checkpointCollectedGems.set(gem, true);
		}
		this.checkpointHeldPowerup = this.marble.heldPowerup;
		this.displayAlert("Checkpoint reached!");
		AudioManager.playSound(ResourceLoader.getResource('data/sound/checkpoint.wav', ResourceLoader.getAudio, this.soundResources));
	}

	/** Resets to the last stored checkpoint state. */
	public function loadCheckpointState() {
		var marble = this.marble;
		// Determine where to spawn the marble
		var offset = new Vector(0, 0, 3);
		var add = ""; // (this.currentCheckpoint.srcElement as any)?.add || this.currentCheckpointTrigger?.element.add;
		if (this.currentCheckpoint.elem.fields.exists('add')) {
			add = this.currentCheckpoint.elem.fields.get('add')[0];
		}
		var sub = "";
		if (this.currentCheckpoint.elem.fields.exists('sub')) {
			sub = this.currentCheckpoint.elem.fields.get('sub')[0];
		}
		if (this.currentCheckpointTrigger != null) {
			if (this.currentCheckpointTrigger.add != null)
				offset = this.currentCheckpointTrigger.add;
		}
		if (add != "") {
			offset = MisParser.parseVector3(add);
			offset.x = -offset.x;
		}
		if (sub != "") {
			offset = MisParser.parseVector3(sub).multiply(-1);
			offset.x = -offset.x;
		}
		var mpos = this.currentCheckpoint.obj.getAbsPos().getPosition().add(offset);
		this.marble.setPosition(mpos.x, mpos.y, mpos.z);
		marble.velocity.load(new Vector(0, 0, 0));
		marble.omega.load(new Vector(0, 0, 0));
		Console.log('Respawn:');
		Console.log('Marble Position: ${mpos.x} ${mpos.y} ${mpos.z}');
		Console.log('Marble Velocity: ${marble.velocity.x} ${marble.velocity.y} ${marble.velocity.z}');
		Console.log('Marble Angular: ${marble.omega.x} ${marble.omega.y} ${marble.omega.z}');
		// Set camera orientation
		var euler = this.currentCheckpoint.obj.getRotationQuat().toEuler();
		this.marble.camera.CameraYaw = euler.z + Math.PI / 2;
		this.marble.camera.CameraPitch = 0.45;
		this.marble.camera.nextCameraYaw = this.marble.camera.CameraYaw;
		this.marble.camera.nextCameraPitch = this.marble.camera.CameraPitch;
		this.marble.camera.oob = false;
		@:privateAccess this.marble.superBounceEnableTime = -1e8;
		@:privateAccess this.marble.shockAbsorberEnableTime = -1e8;
		@:privateAccess this.marble.helicopterEnableTime = -1e8;
		@:privateAccess this.marble.megaMarbleEnableTime = -1e8;
		this.blastAmount = this.cheeckpointBlast;
		if (this.isRecording) {
			this.replay.recordCameraState(this.marble.camera.CameraYaw, this.marble.camera.CameraPitch);
			this.replay.recordMarbleInput(0, 0);
			this.replay.recordMarbleState(mpos, marble.velocity, marble.getRotationQuat(), marble.omega);
			this.replay.recordMarbleStateFlags(false, false, true, false);
		}
		var gravityField = ""; // (this.currentCheckpoint.srcElement as any) ?.gravity || this.currentCheckpointTrigger?.element.gravity;
		if (this.currentCheckpoint.elem.fields.exists('gravity')) {
			gravityField = this.currentCheckpoint.elem.fields.get('gravity')[0];
		}
		if (this.currentCheckpointTrigger != null) {
			if (@:privateAccess this.currentCheckpointTrigger.element.fields.exists('gravity')) {
				gravityField = @:privateAccess this.currentCheckpointTrigger.element.fields.get('gravity')[0];
			}
		}
		if (MisParser.parseBoolean(gravityField)) {
			// In this case, we set the gravity to the relative "up" vector of the checkpoint shape.
			var up = new Vector(0, 0, 1);
			up.transform(this.currentCheckpoint.obj.getRotationQuat().toMatrix());
			this.setUp(up, this.timeState, true);
		} else {
			// Otherwise, we restore gravity to what was stored.
			this.setUp(this.checkpointUp, this.timeState, true);
		}
		// Restore gem states
		for (gem in this.gems) {
			if (gem.pickedUp && !this.checkpointCollectedGems.exists(gem)) {
				gem.reset();
				this.gemCount--;
			}
		}
		this.playGui.formatGemCounter(this.gemCount, this.totalGems);
		this.playGui.setCenterText('none');
		this.clearSchedule();
		this.outOfBounds = false;
		this.deselectPowerUp(); // Always deselect first
		// Wait a bit to select the powerup to prevent immediately using it incase the user skipped the OOB screen by clicking
		if (this.checkpointHeldPowerup != null)
			this.schedule(this.timeState.currentAttemptTime + 0.5, () -> this.pickUpPowerUp(this.checkpointHeldPowerup));
		AudioManager.playSound(ResourceLoader.getResource('data/sound/spawn.wav', ResourceLoader.getAudio, this.soundResources));
	}

	public function setCursorLock(enabled:Bool) {
		this.cursorLock = enabled;
		if (enabled) {
			if (this.marble != null)
				this.marble.camera.lockCursor();
		} else {
			if (this.marble != null)
				this.marble.camera.unlockCursor();
		}
	}

	public function saveReplay() {
		this.replay.name = MarbleGame.instance.recordingName;
		#if hl
		sys.FileSystem.createDirectory(haxe.io.Path.join([Settings.settingsDir, "data", "replays"]));
		var replayPath = haxe.io.Path.join([
			Settings.settingsDir,
			"data",
			"replays",
			'${this.replay.name}.mbr'
		]);
		if (sys.FileSystem.exists(replayPath)) {
			var count = 1;
			var found = false;
			while (!found) {
				replayPath = haxe.io.Path.join([
					Settings.settingsDir,
					"data",
					"replays",
					'${this.replay.name} (${count}).mbr'
				]);
				if (!sys.FileSystem.exists(replayPath)) {
					this.replay.name += ' (${count})';
					found = true;
				} else {
					count++;
				}
			}
		}
		var replayBytes = this.replay.write();
		sys.io.File.saveBytes(replayPath, replayBytes);
		#end
		#if js
		var replayBytes = this.replay.write();
		var blob = new js.html.Blob([replayBytes.getData()], {
			type: 'application/octet-stream'
		});
		var url = js.html.URL.createObjectURL(blob);
		var fname = '${this.replay.name}.mbr';
		var element = js.Browser.document.createElement('a');
		element.setAttribute('href', url);
		element.setAttribute('download', fname);

		element.style.display = 'none';
		js.Browser.document.body.appendChild(element);

		element.click();

		js.Browser.document.body.removeChild(element);
		js.html.URL.revokeObjectURL(url);
		#end
	}

	public function dispose() {
		// Gotta add the timesinceload to our stats
		if (!this.isWatching) {
			Settings.playStatistics.totalTime += this.timeState.timeSinceLoad;

			if (!Settings.levelStatistics.exists(mission.path)) {
				Settings.levelStatistics.set(mission.path, {
					oobs: 0,
					respawns: 0,
					totalTime: this.timeState.timeSinceLoad,
				});
			} else {
				Settings.levelStatistics[mission.path].totalTime += this.timeState.timeSinceLoad;
			}
		}

		this.playGui.dispose();
		scene.removeChildren();

		for (interior in this.interiors) {
			interior.dispose();
		}
		for (pathedInteriors in this.pathedInteriors) {
			pathedInteriors.dispose();
		}
		for (marble in this.marbles) {
			marble.dispose();
		}
		for (dtsObject in this.dtsObjects) {
			dtsObject.dispose();
		}
		for (trigger in this.triggers) {
			trigger.dispose();
		}
		for (soundResource in this.soundResources) {
			soundResource.release();
		}
		for (textureResource in this.textureResources) {
			textureResource.release();
		}

		sky.dispose();

		this._disposed = true;
		AudioManager.stopAllSounds();
		AudioManager.playShell();
	}
}

typedef ScheduleInfo = {
	var id:Float;
	var stringId:String;
	var time:Float;
	var callBack:Void->Any;
}

abstract class Scheduler {
	var scheduled:Array<ScheduleInfo> = [];

	public function tickSchedule(time:Float) {
		for (item in this.scheduled) {
			if (time >= item.time) {
				this.scheduled.remove(item);
				item.callBack();
			}
		}
	}

	public function schedule(time:Float, callback:Void->Any, stringId:String = null) {
		var id = Math.random();
		this.scheduled.push({
			id: id,
			stringId: '${id}',
			time: time,
			callBack: callback
		});
		return id;
	}

	/** Cancels a schedule */
	public function cancel(id:Float) {
		var idx = this.scheduled.filter((val) -> {
			return val.id == id;
		});
		if (idx.length == 0)
			return;
		this.scheduled.remove(idx[0]);
	}

	public function clearSchedule() {
		this.scheduled = [];
	}

	public function clearScheduleId(id:String) {
		var idx = this.scheduled.filter((val) -> {
			return val.stringId == id;
		});
		if (idx.length == 0)
			return;
		this.scheduled.remove(idx[0]);
	}
}
