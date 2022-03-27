// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protobuf_serializers;

Map<String, dynamic> writeToJsonMap(FieldSet fs) {
  dynamic convertToMap(dynamic fieldValue, int fieldType) {
    var baseType = PbFieldType.baseType(fieldType);

    if (isRepeatedFieldType(fieldType)) {
      return List.from(fieldValue.map((e) => convertToMap(e, baseType)));
    }

    switch (baseType) {
      case PbFieldType.BOOL_BIT:
      case PbFieldType.STRING_BIT:
      case PbFieldType.FLOAT_BIT:
      case PbFieldType.DOUBLE_BIT:
      case PbFieldType.INT32_BIT:
      case PbFieldType.SINT32_BIT:
      case PbFieldType.UINT32_BIT:
      case PbFieldType.FIXED32_BIT:
      case PbFieldType.SFIXED32_BIT:
        return fieldValue;
      case PbFieldType.BYTES_BIT:
        // Encode 'bytes' as a base64-encoded string.
        return base64Encode(fieldValue as List<int>);
      case PbFieldType.ENUM_BIT:
        return fieldValue.value; // assume |value| < 2^52
      case PbFieldType.INT64_BIT:
      case PbFieldType.SINT64_BIT:
      case PbFieldType.SFIXED64_BIT:
        return fieldValue.toString();
      case PbFieldType.UINT64_BIT:
      case PbFieldType.FIXED64_BIT:
        return fieldValue.toStringUnsigned();
      case PbFieldType.GROUP_BIT:
      case PbFieldType.MESSAGE_BIT:
        return fieldValue.writeToJsonMap();
      default:
        throw 'Unknown type $fieldType';
    }
  }

  List _writeMap(dynamic fieldValue, MapFieldInfo fi) =>
      List.from(fieldValue.entries.map((MapEntry e) => {
            '${PbMap.keyFieldNumber}': convertToMap(e.key, fi.keyFieldType!),
            '${PbMap.valueFieldNumber}':
                convertToMap(e.value, fi.valueFieldType!)
          }));

  var result = <String, dynamic>{};
  for (var fi in fs.infosSortedByTag) {
    var value = fs.values[fi.index!];
    if (value == null || (value is List && value.isEmpty)) {
      continue; // It's missing, repeated, or an empty byte array.
    }
    if (isMapFieldType(fi.type)) {
      result['${fi.tagNumber}'] =
          _writeMap(value, fi as MapFieldInfo<dynamic, dynamic>);
      continue;
    }
    result['${fi.tagNumber}'] = convertToMap(value, fi.type);
  }
  if (fs.hasExtensions) {
    for (var tagNumber in _sorted(fs.extensions!.tagNumbers)) {
      var value = fs.extensions!.values[tagNumber];
      if (value is List && value.isEmpty) {
        continue; // It's repeated or an empty byte array.
      }
      var fi = fs.extensions!.getInfoOrNull(tagNumber)!;
      result['$tagNumber'] = convertToMap(value, fi.type);
    }
  }
  return result;
}

// Merge fields from a previously decoded JSON object.
// (Called recursively on nested messages.)
void mergeFromJsonMap(
    FieldSet fs, Map<String, dynamic> json, ExtensionRegistry? registry) {
  final keys = json.keys;
  final info = fs.meta;
  for (var key in keys) {
    var fi = info.byTagAsString[key];
    if (fi == null) {
      if (registry == null) continue; // Unknown tag; skip
      fi = registry.getExtension(fs.messageName, int.parse(key));
      if (fi == null) continue; // Unknown tag; skip
    }
    if (fi.isMapField) {
      _appendJsonMap(
          info, fs, json[key], fi as MapFieldInfo<dynamic, dynamic>, registry);
    } else if (fi.isRepeated) {
      _appendJsonList(info, fs, json[key], fi, registry);
    } else {
      _setJsonField(info, fs, json[key], fi, registry);
    }
  }
}

void _appendJsonList(BuilderInfo meta, FieldSet fs, List jsonList, FieldInfo fi,
    ExtensionRegistry? registry) {
  final repeated = fi.ensureRepeatedField(meta, fs);
  // Micro optimization. Using "for in" generates the following and iterator
  // alloc:
  //   for (t1 = J.get$iterator$ax(json), t2 = fi.tagNumber, t3 = fi.type,
  //       t4 = J.getInterceptor$ax(repeated); t1.moveNext$0();)
  for (var i = 0, len = jsonList.length; i < len; i++) {
    var value = jsonList[i];
    var convertedValue =
        _convertJsonValue(meta, fs, value, fi.tagNumber, fi.type, registry);
    // In the case of an unknown enum value, the converted value may return
    // null. The default enum value should be used in these cases, which is
    // stored in the FieldInfo.
    convertedValue ??= fi.defaultEnumValue;
    repeated.add(convertedValue);
  }
}

void _appendJsonMap(BuilderInfo meta, FieldSet fs, List jsonList,
    MapFieldInfo fi, ExtensionRegistry? registry) {
  final entryMeta = fi.mapEntryBuilderInfo;
  final map = fi.ensureMapField(meta, fs) as PbMap<dynamic, dynamic>;
  for (var jsonEntryDynamic in jsonList) {
    var jsonEntry = jsonEntryDynamic as Map<String, dynamic>;
    final entryFieldSet = FieldSet(null, entryMeta, null);
    final convertedKey = _convertJsonValue(
        entryMeta,
        entryFieldSet,
        jsonEntry['${PbMap.keyFieldNumber}'],
        PbMap.keyFieldNumber,
        fi.keyFieldType!,
        registry);
    var convertedValue = _convertJsonValue(
        entryMeta,
        entryFieldSet,
        jsonEntry['${PbMap.valueFieldNumber}'],
        PbMap.valueFieldNumber,
        fi.valueFieldType!,
        registry);
    // In the case of an unknown enum value, the converted value may return
    // null. The default enum value should be used in these cases, which is
    // stored in the FieldInfo.
    convertedValue ??= fi.defaultEnumValue;
    map[convertedKey] = convertedValue;
  }
}

void _setJsonField(BuilderInfo meta, FieldSet fs, json, FieldInfo fi,
    ExtensionRegistry? registry) {
  final value =
      _convertJsonValue(meta, fs, json, fi.tagNumber, fi.type, registry);
  if (value == null) return;
  // _convertJsonValue throws exception when it fails to do conversion.
  // Therefore we run _validateField for debug builds only to validate
  // correctness of conversion.
  assert(() {
    fs.validateField(fi, value);
    return true;
  }());
  fs.setFieldUnchecked(meta, fi, value);
}

/// Converts [value] from the Json format to the Dart data type
/// suitable for inserting into the corresponding [GeneratedMessage] field.
///
/// Returns the converted value.  This function returns `null` if it is an
/// unknown enum value, in which case the caller should figure out the default
/// enum value to return instead.
/// This function throws [ArgumentError] if it cannot convert the value.
dynamic _convertJsonValue(BuilderInfo meta, FieldSet fs, value, int tagNumber,
    int fieldType, ExtensionRegistry? registry) {
  String expectedType; // for exception message
  switch (PbFieldType.baseType(fieldType)) {
    case PbFieldType.BOOL_BIT:
      if (value is bool) {
        return value;
      } else if (value is String) {
        if (value == 'true') {
          return true;
        } else if (value == 'false') {
          return false;
        }
      } else if (value is num) {
        if (value == 1) {
          return true;
        } else if (value == 0) {
          return false;
        }
      }
      expectedType = 'bool (true, false, "true", "false", 1, 0)';
      break;
    case PbFieldType.BYTES_BIT:
      if (value is String) {
        return base64Decode(value);
      }
      expectedType = 'Base64 String';
      break;
    case PbFieldType.STRING_BIT:
      if (value is String) {
        return value;
      }
      expectedType = 'String';
      break;
    case PbFieldType.FLOAT_BIT:
    case PbFieldType.DOUBLE_BIT:
      // Allow quoted values, although we don't emit them.
      if (value is double) {
        return value;
      } else if (value is num) {
        return value.toDouble();
      } else if (value is String) {
        return double.parse(value);
      }
      expectedType = 'num or stringified num';
      break;
    case PbFieldType.ENUM_BIT:
      // Allow quoted values, although we don't emit them.
      if (value is String) {
        value = int.parse(value);
      }
      if (value is int) {
        // The following call will return null if the enum value is unknown.
        // In that case, we want the caller to ignore this value, so we return
        // null from this method as well.
        return meta.decodeEnum(tagNumber, registry, value);
      }
      expectedType = 'int or stringified int';
      break;
    case PbFieldType.INT32_BIT:
    case PbFieldType.SINT32_BIT:
    case PbFieldType.UINT32_BIT:
    case PbFieldType.SFIXED32_BIT:
      if (value is int) return value;
      if (value is String) return int.parse(value);
      expectedType = 'int or stringified int';
      break;
    case PbFieldType.FIXED32_BIT:
      int? validatedValue;
      if (value is int) validatedValue = value;
      if (value is String) validatedValue = int.parse(value);
      if (validatedValue != null && validatedValue < 0) {
        validatedValue += 2 * (1 << 31);
      }
      if (validatedValue != null) return validatedValue;
      expectedType = 'int or stringified int';
      break;
    case PbFieldType.INT64_BIT:
    case PbFieldType.SINT64_BIT:
    case PbFieldType.UINT64_BIT:
    case PbFieldType.FIXED64_BIT:
    case PbFieldType.SFIXED64_BIT:
      if (value is int) return Int64(value);
      if (value is String) return Int64.parseInt(value);
      expectedType = 'int or stringified int';
      break;
    case PbFieldType.GROUP_BIT:
    case PbFieldType.MESSAGE_BIT:
      if (value is Map) {
        final messageValue = value as Map<String, dynamic>;
        var subMessage = meta.makeEmptyMessage(tagNumber, registry);
        mergeFromJsonMap(subMessage.fieldSet, messageValue, registry);
        return subMessage;
      }
      expectedType = 'nested message or group';
      break;
    default:
      throw ArgumentError('Unknown type $fieldType');
  }
  throw ArgumentError('Expected type $expectedType, got $value');
}
