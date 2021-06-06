package src;

import sys.io.File;
import src.MarbleWorld;
import src.GameObject;
import collision.CollisionHull;
import collision.CollisionSurface;
import collision.CollisionEntity;
import hxd.FloatBuffer;
import src.DynamicPolygon;
import dts.Sequence;
import h3d.scene.Mesh;
import h3d.prim.Polygon;
import h3d.prim.UV;
import h3d.Vector;
import h3d.Quat;
import dts.Node;
import h3d.mat.BlendMode;
import h3d.mat.Data.Wrap;
import h3d.mat.Texture;
import h3d.mat.Material;
import h3d.scene.Object;
import haxe.io.Path;
import src.ResourceLoader;
import dts.DtsFile;
import h3d.Matrix;
import src.Util;

var DROP_TEXTURE_FOR_ENV_MAP = ['shapes/items/superjump.dts', 'shapes/items/antigravity.dts'];

var dtsMaterials = [
	"oilslick" => {friction: 0.05, restitution: 0.5, force: 0.0},
	"base.slick" => {friction: 0.05, restitution: 0.5, force: 0.0},
	"ice.slick" => {friction: 0.05, restitution: 0.5, force: 0.0},
	"bumper-rubber" => {friction: 0.5, restitution: 0.0, force: 15.0},
	"triang-side" => {friction: 0.5, restitution: 0.0, force: 15.0},
	"triang-top" => {friction: 0.5, restitution: 0.0, force: 15.0},
	"pball-round-side" => {friction: 0.5, restitution: 0.0, force: 15.0},
	"pball-round-top" => {friction: 0.5, restitution: 0.0, force: 15.0},
	"pball-round-bottm" => {friction: 0.5, restitution: 0.0, force: 15.0}
];

typedef GraphNode = {
	var index:Int;
	var node:Node;
	var children:Array<GraphNode>;
	var parent:GraphNode;
}

typedef MaterialGeometry = {
	var vertices:Array<Vector>;
	var normals:Array<Vector>;
	var uvs:Array<UV>;
	var indices:Array<Int>;
}

typedef SkinMeshData = {
	var meshIndex:Int;
	var vertices:Array<Vector>;
	var normals:Array<Vector>;
	var indices:Array<Int>;
	var geometry:Object;
}

@:publicFields
class DtsObject extends GameObject {
	var dtsPath:String;
	var directoryPath:String;
	var dts:DtsFile;

	var level:MarbleWorld;

	var materials:Array<Material> = [];
	var materialInfos:Map<Material, Array<String>> = new Map();
	var matNameOverride:Map<String, String> = new Map();

	var sequenceKeyframeOverride:Map<Sequence, Float> = new Map();
	var lastSequenceKeyframes:Map<Sequence, Float> = new Map();

	var graphNodes:Array<Object> = [];

	var useInstancing:Bool = true;
	var isTSStatic:Bool;
	var isCollideable:Bool;
	var showSequences:Bool = true;
	var hasNonVisualSequences:Bool = true;
	var isInstanced:Bool = false;

	var _regenNormals:Bool = false;

	var skinMeshData:SkinMeshData;

	var rootObject:Object;
	var colliders:Array<CollisionEntity>;

	var mountPointNodes:Array<Int>;

	public function new() {
		super();
	}

	public function init(level:MarbleWorld) {
		this.dts = ResourceLoader.loadDts(this.dtsPath);
		this.directoryPath = Path.directory(this.dtsPath);
		this.level = level;

		isInstanced = this.level.instanceManager.isInstanced(this) && useInstancing;
		if (!isInstanced)
			this.computeMaterials();

		var graphNodes = [];
		var rootNodesIdx = [];
		colliders = [];
		this.mountPointNodes = [for (i in 0...32) -1];

		for (i in 0...this.dts.nodes.length) {
			graphNodes.push(new Object());
		}

		for (i in 0...this.dts.nodes.length) {
			var node = this.dts.nodes[i];
			if (node.parent != -1) {
				graphNodes[node.parent].addChild(graphNodes[i]);
			} else {
				rootNodesIdx.push(i);
			}
		}

		this.graphNodes = graphNodes;
		// this.rootGraphNodes = graphNodes.filter(node -> node.parent == null);

		var affectedBySequences = this.dts.sequences.length > 0 ? (this.dts.sequences[0].rotationMatters.length < 0 ? 0 : this.dts.sequences[0].rotationMatters[0]) | (this.dts.sequences[0].translationMatters.length > 0 ? this.dts.sequences[0].translationMatters[0] : 0) : 0;

		for (i in 0...dts.nodes.length) {
			var objects = dts.objects.filter(object -> object.node == i);
			var sequenceAffected = ((1 << i) & affectedBySequences) != 0;

			if (dts.names[dts.nodes[i].name].substr(0, 5) == "mount") {
				var mountindex = dts.names[dts.nodes[i].name].substr(5);
				var mountNode = Std.parseInt(mountindex);
				mountPointNodes[mountNode] = i;
			}

			for (object in objects) {
				var isCollisionObject = dts.names[object.name].substr(0, 3).toLowerCase() == "col";

				if (isCollisionObject)
					continue;

				for (j in object.firstMesh...(object.firstMesh + object.numMeshes)) {
					if (j >= this.dts.meshes.length)
						continue;

					var mesh = this.dts.meshes[j];
					if (mesh == null)
						continue;

					if (!isInstanced) {
						var vertices = mesh.vertices.map(v -> new Vector(v.x, v.y, v.z));
						var vertexNormals = mesh.normals.map(v -> new Vector(v.x, v.y, v.z));

						var geometry = this.generateMaterialGeometry(mesh, vertices, vertexNormals);
						for (k in 0...geometry.length) {
							if (geometry[k].vertices.length == 0)
								continue;

							var poly = new Polygon(geometry[k].vertices.map(x -> x.toPoint()));
							poly.normals = geometry[k].normals.map(x -> x.toPoint());
							poly.uvs = geometry[k].uvs;

							var obj = new Mesh(poly, materials[k], this.graphNodes[i]);
						}
					} else {
						var usedMats = [];

						for (prim in mesh.primitives) {
							if (!usedMats.contains(prim.matIndex)) {
								usedMats.push(prim.matIndex);
							}
						}

						for (k in usedMats) {
							var obj = new Object(this.graphNodes[i]);
						}
					}
				}
			}
		}

		if (this.isCollideable) {
			for (i in 0...dts.nodes.length) {
				var objects = dts.objects.filter(object -> object.node == i);
				var meshSurfaces = [];
				var collider = new CollisionHull();

				for (object in objects) {
					var isCollisionObject = dts.names[object.name].substr(0, 3).toLowerCase() == "col";

					if (isCollisionObject) {
						for (j in object.firstMesh...(object.firstMesh + object.numMeshes)) {
							if (j >= this.dts.meshes.length)
								continue;

							var mesh = this.dts.meshes[j];
							if (mesh == null)
								continue;

							var vertices = mesh.vertices.map(v -> new Vector(v.x, v.y, v.z));
							var vertexNormals = mesh.normals.map(v -> new Vector(v.x, v.y, v.z));

							var surfaces = this.generateCollisionGeometry(mesh, vertices, vertexNormals);
							for (surface in surfaces)
								collider.addSurface(surface);
							meshSurfaces = meshSurfaces.concat(surfaces);
						}
					}
				}
				if (meshSurfaces.length != 0)
					colliders.push(collider);
				else
					colliders.push(null);
			}
		}

		this.updateNodeTransforms();

		for (i in 0...this.dts.meshes.length) {
			var mesh = this.dts.meshes[i];
			if (mesh == null)
				continue;

			if (mesh.meshType == 1) {
				var skinObj = new Object();

				if (!isInstanced) {
					var vertices = mesh.vertices.map(v -> new Vector(v.x, v.y, v.z));
					var vertexNormals = mesh.normals.map(v -> new Vector(v.x, v.y, v.z));
					var geometry = this.generateMaterialGeometry(mesh, vertices, vertexNormals);
					for (k in 0...geometry.length) {
						if (geometry[k].vertices.length == 0)
							continue;

						var poly = new DynamicPolygon(geometry[k].vertices.map(x -> x.toPoint()));
						poly.normals = geometry[k].normals.map(x -> x.toPoint());
						poly.uvs = geometry[k].uvs;

						var obj = new Mesh(poly, materials[k], skinObj);
					}
					skinMeshData = {
						meshIndex: i,
						vertices: vertices,
						normals: vertexNormals,
						indices: [],
						geometry: skinObj
					};
					var idx = geometry.map(x -> x.indices);
					for (indexes in idx) {
						skinMeshData.indices = skinMeshData.indices.concat(indexes);
					}
				} else {
					var usedMats = [];

					for (prim in mesh.primitives) {
						if (!usedMats.contains(prim.matIndex)) {
							usedMats.push(prim.matIndex);
						}
					}

					for (k in usedMats) {
						var obj = new Object(skinObj);
					}
					skinMeshData = {
						meshIndex: i,
						vertices: [],
						normals: [],
						indices: [],
						geometry: skinObj
					};
				}
			}
		}

		rootObject = new Object(this);

		for (i in rootNodesIdx) {
			rootObject.addChild(this.graphNodes[i]);
		}

		if (this.skinMeshData != null) {
			rootObject.addChild(this.skinMeshData.geometry);
		}

		rootObject.scaleX = -1;
	}

	function computeMaterials() {
		var environmentMaterial:Material = null;

		for (i in 0...dts.matNames.length) {
			var matName = matNameOverride.exists(dts.matNames[i]) ? matNameOverride.get(dts.matNames[i]) : this.dts.matNames[i];
			var flags = dts.matFlags[i];
			var fullNames = ResourceLoader.getFullNamesOf(this.directoryPath + '/' + matName).filter(x -> Path.extension(x) != "dts");
			var fullName = fullNames.length > 0 ? fullNames[0] : null;

			if (this.isTSStatic && environmentMaterial != null && DROP_TEXTURE_FOR_ENV_MAP.contains(this.dtsPath)) {
				this.materials.push(environmentMaterial);
				continue;
			}

			var material = Material.create();

			if (fullName == null || (this.isTSStatic && ((flags & (1 << 31) > 0)))) {
				if (this.isTSStatic) {
					// TODO USE PBR???
				}
			} else if (Path.extension(fullName) == "ifl") {
				var keyframes = parseIfl(fullName);
				this.materialInfos.set(material, keyframes);
				// TODO IFL SHIT
			} else {
				var texture:Texture = ResourceLoader.getTexture(fullName);
				texture.wrap = Wrap.Repeat;
				material.texture = texture;
				// TODO TRANSLUENCY SHIT
			}
			if (flags & 4 > 0) {
				material.blendMode = BlendMode.Alpha;
				material.mainPass.culling = h3d.mat.Data.Face.Front;
			}
			// TODO TRANSPARENCY SHIT
			if (flags & 8 > 0)
				material.blendMode = BlendMode.Add;
			if (flags & 16 > 0)
				material.blendMode = BlendMode.Sub;

			// if (this.isTSStatic && !(flags & 64 > 0)) {
			// 	// TODO THIS SHIT
			// }
			// ((flags & 32) || environmentMaterial) ? new Materia

			this.materials.push(material);
		}

		if (this.materials.length == 0) {
			var mat = Material.create();
			this.materials.push(mat);
			// TODO THIS
		}
	}

	function parseIfl(path:String) {
		var text = File.getContent(path);
		var lines = text.split('\n');
		var keyframes = [];
		for (line in lines) {
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

		return keyframes;
	}

	function updateNodeTransforms(quaternions:Array<Quat> = null, translations:Array<Vector> = null, bitField = 0xffffffff) {
		for (i in 0...this.graphNodes.length) {
			var translation = this.dts.defaultTranslations[i];
			var rotation = this.dts.defaultRotations[i];
			var mat = Matrix.I();
			var quat = new Quat(rotation.x, rotation.y, rotation.z, rotation.w);
			quat.normalize();
			quat.conjugate();
			quat.toMatrix(mat);
			mat.setPosition(new Vector(translation.x, translation.y, translation.z));
			this.graphNodes[i].setTransform(mat);
			var absTform = this.graphNodes[i].getAbsPos().clone();
			if (this.colliders[i] != null)
				// this.colliders[i].setTransform(Matrix.I());
				this.colliders[i].setTransform(absTform);
		}
	}

	function generateCollisionGeometry(dtsMesh:dts.Mesh, vertices:Array<Vector>, vertexNormals:Array<Vector>) {
		var surfaces = this.dts.matNames.map(x -> new CollisionSurface());
		for (surface in surfaces) {
			surface.points = [];
			surface.normals = [];
			surface.indices = [];
		}
		for (primitive in dtsMesh.primitives) {
			var k = 0;
			var geometrydata = surfaces[primitive.matIndex];
			var material = this.dts.matNames[primitive.matIndex];
			if (dtsMaterials.exists(material)) {
				var data = dtsMaterials.get(material);
				geometrydata.friction = data.friction;
				geometrydata.force = data.force;
				geometrydata.restitution = data.restitution;
			}

			for (i in primitive.firstElement...(primitive.firstElement + primitive.numElements - 2)) {
				var i1 = dtsMesh.indices[i];
				var i2 = dtsMesh.indices[i + 1];
				var i3 = dtsMesh.indices[i + 2];

				if (k % 2 == 0) {
					// Swap the first and last index to mainting correct winding order
					var temp = i1;
					i1 = i3;
					i3 = temp;
				}

				for (index in [i1, i2, i3]) {
					var vertex = vertices[index];
					geometrydata.points.push(new Vector(vertex.x, vertex.y, vertex.z));

					var normal = vertexNormals[index];
					geometrydata.normals.push(new Vector(normal.x, normal.y, normal.z));
				}

				geometrydata.indices.push(geometrydata.indices.length);
				geometrydata.indices.push(geometrydata.indices.length);
				geometrydata.indices.push(geometrydata.indices.length);

				k++;
			}
		}
		for (surface in surfaces) {
			surface.generateBoundingBox();
			// surface.generateNormals();
		}
		return surfaces;
	}

	function generateMaterialGeometry(dtsMesh:dts.Mesh, vertices:Array<Vector>, vertexNormals:Array<Vector>) {
		var materialGeometry:Array<MaterialGeometry> = this.dts.matNames.map(x -> {
			vertices: [],
			normals: [],
			uvs: [],
			indices: []
		});

		for (primitive in dtsMesh.primitives) {
			var k = 0;
			var geometrydata = materialGeometry[primitive.matIndex];

			for (i in primitive.firstElement...(primitive.firstElement + primitive.numElements - 2)) {
				var i1 = dtsMesh.indices[i];
				var i2 = dtsMesh.indices[i + 1];
				var i3 = dtsMesh.indices[i + 2];

				if (k % 2 == 0) {
					// Swap the first and last index to mainting correct winding order
					var temp = i1;
					i1 = i3;
					i3 = temp;
				}

				for (index in [i3, i2, i1]) {
					var vertex = vertices[index];
					geometrydata.vertices.push(new Vector(vertex.x, vertex.y, vertex.z));

					var uv = dtsMesh.uv[index];
					geometrydata.uvs.push(new UV(uv.x, uv.y));

					var normal = vertexNormals[index];
					geometrydata.normals.push(new Vector(normal.x, normal.y, normal.z));
				}

				geometrydata.indices.push(i1);
				geometrydata.indices.push(i2);
				geometrydata.indices.push(i3);

				k++;
			}
		}

		return materialGeometry;
	}

	function mergeMaterialGeometries(materialGeometries:Array<Array<MaterialGeometry>>) {
		var merged = materialGeometries[0].map(x -> {
			vertices: [],
			normals: [],
			uvs: [],
			indices: []
		});

		for (matGeom in materialGeometries) {
			for (i in 0...matGeom.length) {
				merged[i].vertices = merged[i].vertices.concat(matGeom[i].vertices);
				merged[i].normals = merged[i].normals.concat(matGeom[i].normals);
				merged[i].uvs = merged[i].uvs.concat(matGeom[i].uvs);
				merged[i].indices = merged[i].indices.concat(matGeom[i].indices);
			}
		}

		return merged;
	}

	function createGeometryFromMaterialGeometry(materialGeometry:Array<MaterialGeometry>) {
		var geo = new Object();
		for (i in 0...materialGeometry.length) {
			if (materialGeometry[i].vertices.length == 0)
				continue;

			var poly = new Polygon(materialGeometry[i].vertices.map(x -> x.toPoint()));
			poly.normals = materialGeometry[i].normals.map(x -> x.toPoint());
			poly.uvs = materialGeometry[i].uvs;

			var obj = new Mesh(poly, materials[i], geo);
		}
		return geo;
	}

	public function update(currentTime:Float, dt:Float) {
		for (sequence in this.dts.sequences) {
			if (!this.showSequences)
				break;
			if (!this.hasNonVisualSequences)
				break;

			var rot = sequence.rotationMatters.length > 0 ? sequence.rotationMatters[0] : 0;
			var trans = sequence.translationMatters.length > 0 ? sequence.translationMatters[0] : 0;
			var affectedCount = 0;
			var completion = (currentTime + dt) / sequence.duration;

			var quaternions:Array<Quat> = null;
			var translations:Array<Vector> = null;

			var actualKeyframe = this.sequenceKeyframeOverride.exists(sequence) ? this.sequenceKeyframeOverride.get(sequence) : ((completion * sequence.numKeyFrames) % sequence.numKeyFrames);
			if (this.lastSequenceKeyframes.get(sequence) == actualKeyframe)
				continue;
			lastSequenceKeyframes.set(sequence, actualKeyframe);

			var keyframeLow = Math.floor(actualKeyframe);
			var keyframeHigh = Math.ceil(actualKeyframe) % sequence.numKeyFrames;
			var t = (actualKeyframe - keyframeLow) % 1;

			if (rot > 0) {
				quaternions = [];

				for (i in 0...this.dts.nodes.length) {
					var affected = ((1 << i) & rot) != 0;

					if (affected) {
						var rot1 = this.dts.nodeRotations[sequence.numKeyFrames * affectedCount + keyframeLow];
						var rot2 = this.dts.nodeRotations[sequence.numKeyFrames * affectedCount + keyframeHigh];

						var q1 = new Quat(rot1.x, rot1.y, rot1.z, rot1.w);
						q1.normalize();
						q1.conjugate();

						var q2 = new Quat(rot2.x, rot2.y, rot2.z, rot2.w);
						q2.normalize();
						q2.conjugate();

						var quat = new Quat();
						quat.slerp(q1, q2, t);
						quat.normalize();

						this.graphNodes[i].setRotationQuat(quat);
						affectedCount++;
						// quaternions.push(quat);
					} else {
						var rotation = this.dts.defaultRotations[i];
						var quat = new Quat(rotation.x, rotation.y, rotation.z, rotation.w);
						quat.normalize();
						quat.conjugate();
						this.graphNodes[i].setRotationQuat(quat);
						// quaternions.push(quat);
					}
				}
			}

			affectedCount = 0;
			if (trans > 0) {
				translations = [];

				for (i in 0...this.dts.nodes.length) {
					var affected = ((1 << i) & trans) != 0;

					if (affected) {
						var trans1 = this.dts.nodeTranslations[sequence.numKeyFrames * affectedCount + keyframeLow];
						var trans2 = this.dts.nodeTranslations[sequence.numKeyFrames * affectedCount + keyframeHigh];

						var v1 = new Vector(trans1.x, trans1.y, trans1.z);
						var v2 = new Vector(trans2.x, trans2.y, trans2.z);
						var trans = Util.lerpThreeVectors(v1, v2, t);
						this.graphNodes[i].setPosition(trans.x, trans.y, trans.z);

						// translations.push(Util.lerpThreeVectors(v1, v2, t));
					} else {
						var translation = this.dts.defaultTranslations[i];
						var trans = new Vector(translation.x, translation.y, translation.z);
						this.graphNodes[i].setPosition(trans.x, trans.y, trans.z);
						// translations.push();
					}
				}
			}
		}

		if (this.skinMeshData != null && !isInstanced) {
			var info = this.skinMeshData;
			var mesh = this.dts.meshes[info.meshIndex];

			for (i in 0...info.vertices.length) {
				info.vertices[i] = new Vector();
				info.normals[i] = new Vector();
			}

			var boneTransformations = [];

			for (i in 0...mesh.nodeIndices.length) {
				var mat = mesh.initialTransforms[i].clone();
				mat.transpose();
				var tform = this.graphNodes[mesh.nodeIndices[i]].getRelPos(this).clone();
				mat.multiply(mat, tform);

				boneTransformations.push(mat);
			}

			for (i in 0...mesh.vertexIndices.length) {
				var vIndex = mesh.vertexIndices[i];
				var vertex = mesh.vertices[vIndex];
				var normal = mesh.normals[vIndex];

				var vec = new Vector();
				var vec2 = new Vector();

				vec.set(vertex.x, vertex.y, vertex.z);
				vec2.set(normal.x, normal.y, normal.z);
				var mat = boneTransformations[mesh.boneIndices[i]];

				vec.transform(mat);
				vec = vec.multiply(mesh.weights[i]);
				vec2.transform3x3(mat);
				vec2 = vec2.multiply(mesh.weights[i]);

				info.vertices[vIndex] = info.vertices[vIndex].add(vec);
				info.normals[vIndex] = info.normals[vIndex].add(vec2);
			}

			for (i in 0...info.normals.length) {
				var norm = info.normals[i];
				var len2 = norm.lengthSq();

				if (len2 > 0.01)
					norm.normalize();
			}

			var meshIndex = 0;
			var mesh:Mesh = cast info.geometry.children[meshIndex];
			var prim:DynamicPolygon = cast mesh.primitive;
			var vbuffer:FloatBuffer = null;
			if (prim.buffer != null) {
				vbuffer = prim.getBuffer(prim.points.length);
			}
			var pos = 0;
			for (i in info.indices) {
				if (pos >= prim.points.length) {
					meshIndex++;
					if (prim.buffer != null) {
						prim.addNormals();
						prim.flush();
					}
					mesh.primitive = prim;
					mesh = cast info.geometry.children[meshIndex];
					prim = cast mesh.primitive;
					pos = 0;
					if (prim.buffer != null) {
						vbuffer = prim.getBuffer(prim.points.length);
					}
				}
				var vertex = info.vertices[i];
				var normal = info.normals[i];
				prim.points[pos] = vertex.toPoint();
				if (prim.buffer != null) {
					prim.dirtyFlags[pos] = true;
				}
				pos++;
			}
			if (prim.buffer != null) {
				prim.addNormals();
				prim.flush();
			}
			if (_regenNormals) {
				_regenNormals = false;
			}
		}

		if (!this.isInstanced) {
			for (i in 0...this.materials.length) {
				var info = this.materialInfos.get(this.materials[i]);
				if (info == null)
					continue;

				var iflSequence = this.dts.sequences.filter(seq -> seq.iflMatters.length > 0 ? seq.iflMatters[0] > 0 : false);
				if (iflSequence.length == 0 || !this.showSequences)
					continue;

				var completion = (currentTime + dt) / (iflSequence[0].duration);
				var keyframe = Math.floor(completion * info.length) % info.length;
				var currentFile = info[keyframe];
				var texture = ResourceLoader.getTexture(this.directoryPath + '/' + currentFile);

				var flags = this.dts.matFlags[i];
				if (flags & 1 > 0 || flags & 2 > 0)
					texture.wrap = Wrap.Repeat;

				this.materials[i].texture = texture;
			}
		}

		for (i in 0...this.colliders.length) {
			var absTform = this.graphNodes[i].getAbsPos().clone();
			if (this.colliders[i] != null)
				this.colliders[i].setTransform(absTform);
		}
	}

	public function getMountTransform(mountPoint:Int) {
		if (mountPoint < 32) {
			var ni = mountPointNodes[mountPoint];
			if (ni != -1) {
				var mtransform = this.graphNodes[ni].getAbsPos().clone();
				return mtransform;
			}
		}
		return this.getTransform().clone();
	}
}