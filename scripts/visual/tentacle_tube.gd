extends RefCounted
class_name TentacleTubeBuilder

static func build(points: PackedVector3Array, base_radius: float, tip_radius: float, radial_segments: int = 9) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var rings: int = points.size()
	for i in rings:
		var p := points[i]
		var tangent: Vector3
		if i == 0:
			tangent = (points[1] - points[0]).normalized()
		elif i == rings - 1:
			tangent = (points[rings - 1] - points[rings - 2]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()

		var reference := Vector3.UP
		if absf(tangent.dot(reference)) > 0.88:
			reference = Vector3.RIGHT
		var normal_axis := tangent.cross(reference).normalized()
		var binormal := tangent.cross(normal_axis).normalized()
		var t: float = float(i) / float(maxi(rings - 1, 1))
		var radius: float = lerpf(base_radius, tip_radius, pow(t, 0.82))

		for j in radial_segments:
			var angle: float = TAU * float(j) / float(radial_segments)
			var outward := (normal_axis * cos(angle) + binormal * sin(angle)).normalized()
			vertices.append(p + outward * radius)
			normals.append(outward)
			uvs.append(Vector2(float(j) / float(radial_segments), t))

	for i in range(rings - 1):
		for j in radial_segments:
			var next_j: int = (j + 1) % radial_segments
			var a: int = i * radial_segments + j
			var b: int = i * radial_segments + next_j
			var c: int = (i + 1) * radial_segments + j
			var d: int = (i + 1) * radial_segments + next_j
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
