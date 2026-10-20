class_name EditorGeometry
extends RefCounted
## Геометрические помощники для визуализации и выбора деталей.

const EPSILON := 0.00001


static func beam_transform(a: Vector3, b: Vector3) -> Transform3D:
	var delta := b - a
	var length := delta.length()
	if length < 0.0001:
		return Transform3D(Basis.IDENTITY, a)
	var direction := delta / length
	var rotation := Basis(Quaternion(Vector3.UP, direction))
	return Transform3D(rotation * Basis.from_scale(Vector3(1.0, length, 1.0)), (a + b) * 0.5)


static func polygon_normal(vertices: PackedVector3Array) -> Vector3:
	var normal := Vector3.ZERO
	var count := vertices.size()
	if count < 3:
		return Vector3.UP
	for i in count:
		var current := vertices[i]
		var next := vertices[(i + 1) % count]
		normal.x += (current.y - next.y) * (current.z + next.z)
		normal.y += (current.z - next.z) * (current.x + next.x)
		normal.z += (current.x - next.x) * (current.y + next.y)
	if normal.length_squared() < EPSILON:
		return Vector3.UP
	return normal.normalized()


static func make_panel_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	if vertices.size() < 3:
		return ArrayMesh.new()
	var triangles := PackedInt32Array()
	for i in range(1, vertices.size() - 1):
		triangles.append_array(PackedInt32Array([0, i, i + 1]))
	return _build_flat_mesh(vertices, triangles)


static func make_cube_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	if vertices.size() != 8:
		return ArrayMesh.new()
	var triangles := PackedInt32Array([
		0, 3, 2, 0, 2, 1,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		1, 2, 6, 1, 6, 5,
		2, 3, 7, 2, 7, 6,
		3, 0, 4, 3, 4, 7,
	])
	return _build_flat_mesh(vertices, triangles)


static func ray_triangle(
	ray_origin: Vector3,
	ray_dir: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> Variant:
	var edge1 := b - a
	var edge2 := c - a
	var h := ray_dir.cross(edge2)
	var det := edge1.dot(h)
	if absf(det) < 0.0000001:
		return null
	var inv_det := 1.0 / det
	var s := ray_origin - a
	var u := inv_det * s.dot(h)
	if u < 0.0 or u > 1.0:
		return null
	var q := s.cross(edge1)
	var v := inv_det * ray_dir.dot(q)
	if v < 0.0 or u + v > 1.0:
		return null
	var t := inv_det * edge2.dot(q)
	if t <= 0.00001:
		return null
	return ray_origin + ray_dir * t


static func ray_segment_distance(
	ray_origin: Vector3,
	ray_dir: Vector3,
	a: Vector3,
	b: Vector3
) -> Vector2:
	# Возвращает (расстояние до отрезка, параметр вдоль луча).
	var segment := b - a
	var w0 := ray_origin - a
	var a_dot := ray_dir.dot(ray_dir)
	var b_dot := ray_dir.dot(segment)
	var c_dot := segment.dot(segment)
	var d_dot := ray_dir.dot(w0)
	var e_dot := segment.dot(w0)
	var denom := a_dot * c_dot - b_dot * b_dot

	var s := 0.0
	if absf(denom) > EPSILON:
		s = clampf((a_dot * e_dot - b_dot * d_dot) / denom, 0.0, 1.0)

	var closest_segment := a + segment * s
	var along := maxf((closest_segment - ray_origin).dot(ray_dir), 0.0)
	var closest_ray := ray_origin + ray_dir * along

	s = clampf((closest_ray - a).dot(segment) / maxf(c_dot, EPSILON), 0.0, 1.0)
	closest_segment = a + segment * s
	along = maxf((closest_segment - ray_origin).dot(ray_dir), 0.0)
	closest_ray = ray_origin + ray_dir * along

	return Vector2(closest_ray.distance_to(closest_segment), along)


static func closest_point_on_line_to_ray(
	line_origin: Vector3,
	line_dir: Vector3,
	ray_origin: Vector3,
	ray_dir: Vector3
) -> Variant:
	var d1 := line_dir.normalized()
	var d2 := ray_dir.normalized()
	var w0 := line_origin - ray_origin
	var a := d1.dot(d1)
	var b := d1.dot(d2)
	var c := d2.dot(d2)
	var d := d1.dot(w0)
	var e := d2.dot(w0)
	var denom := a * c - b * b
	if absf(denom) < 0.00001:
		return null
	var t := (b * e - c * d) / denom
	return line_origin + d1 * t


static func _build_flat_mesh(vertices: PackedVector3Array, triangles: PackedInt32Array) -> ArrayMesh:
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()

	for i in range(0, triangles.size(), 3):
		var a := vertices[triangles[i]]
		var b := vertices[triangles[i + 1]]
		var c := vertices[triangles[i + 2]]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < EPSILON:
			normal = Vector3.UP
		else:
			normal = normal.normalized()
		out_vertices.append_array(PackedVector3Array([a, b, c]))
		out_normals.append_array(PackedVector3Array([normal, normal, normal]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_vertices
	arrays[Mesh.ARRAY_NORMAL] = out_normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
