package collision;

import h3d.Matrix;
import h3d.col.Bounds;
import octree.IOctreeObject;
import h3d.Vector;
import collision.BVHTree.IBVHObject;

class CollisionSurface implements IOctreeObject implements IBVHObject {
	public var priority:Int;
	public var position:Int;
	public var boundingBox:Bounds;
	public var points:Array<Vector>;
	public var normals:Array<Vector>;
	public var indices:Array<Int>;
	public var friction:Float = 1;
	public var restitution:Float = 1;
	public var force:Float = 0;
	public var edgeData:Array<Int>;
	public var edgeConcavities:Array<Bool>;
	public var originalIndices:Array<Int>;
	public var originalSurfaceIndex:Int;
	public var transformKeys:Array<Int>;

	var _transformedPoints:Array<Vector>;
	var _transformedNormals:Array<Vector>;

	public function new() {}

	public function getElementType() {
		return 2;
	}

	public function generateNormals() {
		var i = 0;
		normals = [for (n in points) null];
		while (i < indices.length) {
			var p1 = points[indices[i]].clone();
			var p2 = points[indices[i + 1]].clone();
			var p3 = points[indices[i + 2]].clone();
			var n = p2.sub(p1).cross(p3.sub(p1)).normalized().multiply(-1);
			normals[indices[i]] = n;
			normals[indices[i + 1]] = n;
			normals[indices[i + 2]] = n;
			i += 3;
		}
	}

	public function generateBoundingBox() {
		var boundingBox = new Bounds();
		boundingBox.xMin = 10e8;
		boundingBox.yMin = 10e8;
		boundingBox.zMin = 10e8;
		boundingBox.xMax = -10e8;
		boundingBox.yMax = -10e8;
		boundingBox.zMax = -10e8;

		for (point in points) {
			if (point.x > boundingBox.xMax) {
				boundingBox.xMax = point.x;
			}
			if (point.x < boundingBox.xMin) {
				boundingBox.xMin = point.x;
			}
			if (point.y > boundingBox.yMax) {
				boundingBox.yMax = point.y;
			}
			if (point.y < boundingBox.yMin) {
				boundingBox.yMin = point.y;
			}
			if (point.z > boundingBox.zMax) {
				boundingBox.zMax = point.z;
			}
			if (point.z < boundingBox.zMin) {
				boundingBox.zMin = point.z;
			}
		}
		this.boundingBox = boundingBox;
	}

	public function setPriority(priority:Int) {
		this.priority = priority;
	}

	public function rayCast(rayOrigin:Vector, rayDirection:Vector):Array<RayIntersectionData> {
		var intersections = [];
		var i = 0;
		while (i < indices.length) {
			var p1 = points[indices[i]].clone();
			var p2 = points[indices[i + 1]].clone();
			var p3 = points[indices[i + 2]].clone();
			var n = normals[indices[i]].clone();
			var d = -p1.dot(n);

			var t = -(rayOrigin.dot(n) + d) / (rayDirection.dot(n));
			var ip = rayOrigin.add(rayDirection.multiply(t));
			ip.w = 1;
			if (t >= 0 && Collision.PointInTriangle(ip, p1, p2, p3)) {
				intersections.push({point: ip, normal: n, object: cast this});
			}
			i += 3;
		}
		return intersections;
	}

	public function support(direction:Vector, transform:Matrix) {
		var furthestDistance:Float = Math.NEGATIVE_INFINITY;
		var furthestVertex:Vector = new Vector();

		for (v in points) {
			var v2 = v.transformed(transform);
			var distance:Float = v2.dot(direction);
			if (distance > furthestDistance) {
				furthestDistance = distance;
				furthestVertex.x = v2.x;
				furthestVertex.y = v2.y;
				furthestVertex.z = v2.z;
			}
		}

		return furthestVertex;
	}

	public function transformTriangle(idx:Int, tform:Matrix, key:Int) {
		if (_transformedPoints == null) {
			_transformedPoints = points.copy();
		}
		if (_transformedNormals == null) {
			_transformedNormals = normals.copy();
		}
		var p1 = indices[idx];
		var p2 = indices[idx + 1];
		var p3 = indices[idx + 2];
		if (transformKeys[p1] != key) {
			_transformedPoints[p1] = points[p1].transformed(tform);
			_transformedNormals[p1] = normals[p1].transformed3x3(tform).normalized();
			transformKeys[p1] = key;
		}
		if (transformKeys[p2] != key) {
			_transformedPoints[p2] = points[p2].transformed(tform);
			transformKeys[p2] = key;
		}
		if (transformKeys[p3] != key) {
			_transformedPoints[p3] = points[p3].transformed(tform);
			transformKeys[p3] = key;
		}
		return {
			v1: _transformedPoints[p1],
			v2: _transformedPoints[p2],
			v3: _transformedPoints[p3],
			n: _transformedNormals[p1]
		};
	}
}
