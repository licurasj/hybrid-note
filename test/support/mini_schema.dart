// Checks the subset of JSON Schema that schema/ uses: type, const, enum,
// anyOf, required, properties, additionalProperties: false, items,
// minItems, maxItems, minLength, maxLength, minimum, pattern and local
// $ref (#/$defs/name). Returns one message per violation. It is no full
// validator: the AI function validates with a real one (T-19 unit 2).
class MiniSchemaValidator {
  MiniSchemaValidator(this.root);

  final Map<String, dynamic> root;

  List<String> validate(Object? value) {
    final List<String> errors = [];
    _check(root, value, r'$', errors);
    return errors;
  }

  void _check(
    Map<String, dynamic> schema,
    Object? value,
    String path,
    List<String> errors,
  ) {
    final Object? ref = schema[r'$ref'];
    if (ref is String) {
      if (!ref.startsWith(r'#/$defs/')) {
        throw ArgumentError('unsupported \$ref $ref');
      }
      final String name = ref.substring(r'#/$defs/'.length);
      final Object? target = (root[r'$defs'] as Map<String, dynamic>?)?[name];
      if (target is! Map<String, dynamic>) {
        throw ArgumentError('unresolved \$ref $ref');
      }
      _check(target, value, path, errors);
      return;
    }

    final Object? anyOf = schema['anyOf'];
    if (anyOf is List) {
      final bool matches = anyOf.any((option) {
        final List<String> optionErrors = [];
        _check(option as Map<String, dynamic>, value, path, optionErrors);
        return optionErrors.isEmpty;
      });
      if (!matches) {
        errors.add('$path: matches none of anyOf');
      }
      return;
    }

    final Object? type = schema['type'];
    if (type != null) {
      final List<dynamic> types = type is List ? type : [type];
      if (!types.any((type) => _isType(value, type as String))) {
        errors.add('$path: expected $type, got ${value.runtimeType}');
        return;
      }
    }

    if (schema.containsKey('const') && value != schema['const']) {
      errors.add('$path: must be ${schema['const']}');
    }

    final Object? allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      errors.add('$path: "$value" not in enum');
    }

    if (value is String) {
      final Object? minLength = schema['minLength'];
      if (minLength is int && value.length < minLength) {
        errors.add('$path: shorter than $minLength');
      }
      final Object? maxLength = schema['maxLength'];
      if (maxLength is int && value.length > maxLength) {
        errors.add('$path: longer than $maxLength');
      }
      final Object? pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(value)) {
        errors.add('$path: does not match $pattern');
      }
    }

    if (value is num) {
      final Object? minimum = schema['minimum'];
      if (minimum is num && value < minimum) {
        errors.add('$path: below $minimum');
      }
    }

    if (value is List) {
      final Object? minItems = schema['minItems'];
      if (minItems is int && value.length < minItems) {
        errors.add('$path: fewer than $minItems items');
      }
      final Object? maxItems = schema['maxItems'];
      if (maxItems is int && value.length > maxItems) {
        errors.add('$path: more than $maxItems items');
      }
      final Object? items = schema['items'];
      if (items is Map<String, dynamic>) {
        for (int i = 0; i < value.length; i++) {
          _check(items, value[i], '$path[$i]', errors);
        }
      }
    }

    if (value is Map) {
      final Map<String, dynamic> properties =
          (schema['properties'] as Map<String, dynamic>?) ?? const {};
      for (final Object? key in (schema['required'] as List?) ?? const []) {
        if (!value.containsKey(key)) {
          errors.add('$path: missing "$key"');
        }
      }
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        final Object? propertySchema = properties[entry.key];
        if (propertySchema is Map<String, dynamic>) {
          _check(propertySchema, entry.value, '$path.${entry.key}', errors);
        } else if (schema['additionalProperties'] == false) {
          errors.add('$path: unexpected "${entry.key}"');
        }
      }
    }
  }

  bool _isType(Object? value, String type) {
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'integer':
        return value is int;
      case 'number':
        return value is num;
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
    }
    throw ArgumentError('unsupported schema type $type');
  }
}
