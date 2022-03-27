// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protobuf;

Object? _writeToProto3Json(FieldSet fs, TypeRegistry typeRegistry) {
  String? convertToMapKey(dynamic key, int keyType) {
    var baseType = PbFieldType.baseType(keyType);

    assert(!isRepeatedFieldType(keyType));

    switch (baseType) {
      case PbFieldType.BOOL_BIT:
        return key ? 'true' : 'false';
      case PbFieldType.STRING_BIT:
        return key;
      case PbFieldType.UINT64_BIT:
        return (key as Int64).toStringUnsigned();
      case PbFieldType.INT32_BIT:
      case PbFieldType.SINT32_BIT:
      case PbFieldType.UINT32_BIT:
      case PbFieldType.FIXED32_BIT:
      case PbFieldType.SFIXED32_BIT:
      case PbFieldType.INT64_BIT:
      case PbFieldType.SINT64_BIT:
      case PbFieldType.SFIXED64_BIT:
      case PbFieldType.FIXED64_BIT:
        return key.toString();
      default:
        throw StateError('Not a valid key type $keyType');
    }
  }

  Object? valueToProto3Json(dynamic fieldValue, int? fieldType) {
    if (fieldValue == null) return null;

    if (isGroupOrMessageFieldType(fieldType!)) {
      return _writeToProto3Json(
          (fieldValue as GeneratedMessage).fieldSet, typeRegistry);
    } else if (isEnumFieldType(fieldType)) {
      return (fieldValue as ProtobufEnum).name;
    } else {
      var baseType = PbFieldType.baseType(fieldType);
      switch (baseType) {
        case PbFieldType.BOOL_BIT:
          return fieldValue ? true : false;
        case PbFieldType.STRING_BIT:
          return fieldValue;
        case PbFieldType.INT32_BIT:
        case PbFieldType.SINT32_BIT:
        case PbFieldType.UINT32_BIT:
        case PbFieldType.FIXED32_BIT:
        case PbFieldType.SFIXED32_BIT:
          return fieldValue;
        case PbFieldType.INT64_BIT:
        case PbFieldType.SINT64_BIT:
        case PbFieldType.SFIXED64_BIT:
        case PbFieldType.FIXED64_BIT:
          return fieldValue.toString();
        case PbFieldType.FLOAT_BIT:
        case PbFieldType.DOUBLE_BIT:
          double value = fieldValue;
          if (value.isNaN) return 'NaN';
          if (value.isInfinite) {
            if (value.isNegative) {
              return '-Infinity';
            } else {
              return 'Infinity';
            }
          }
          return value;
        case PbFieldType.UINT64_BIT:
          return (fieldValue as Int64).toStringUnsigned();
        case PbFieldType.BYTES_BIT:
          return base64Encode(fieldValue);
        default:
          throw StateError(
              'Invariant violation: unexpected value type $fieldType');
      }
    }
  }

  final info = fs.meta;
  if (info.toProto3Json != null) {
    return info.toProto3Json!(fs._message!, typeRegistry);
  }

  var result = <String, dynamic>{};
  for (var fieldInfo in fs.infosSortedByTag) {
    var value = fs.values[fieldInfo.index!];
    if (value == null || (value is List && value.isEmpty)) {
      continue; // It's missing, repeated, or an empty byte array.
    }
    dynamic jsonValue;
    if (fieldInfo.isMapField) {
      jsonValue = (value as PbMap).map((key, entryValue) {
        var mapEntryInfo = fieldInfo as MapFieldInfo;
        return MapEntry(convertToMapKey(key, mapEntryInfo.keyFieldType!),
            valueToProto3Json(entryValue, mapEntryInfo.valueFieldType));
      });
    } else if (fieldInfo.isRepeated) {
      jsonValue = (value as PbListBase)
          .map((element) => valueToProto3Json(element, fieldInfo.type))
          .toList();
    } else {
      jsonValue = valueToProto3Json(value, fieldInfo.type);
    }
    result[fieldInfo.name] = jsonValue;
  }
  // Extensions and unknown fields are not encoded by proto3 JSON.
  return result;
}

/// TODO(paulberry): find a better home for this?
extension _FindFirst<E> on Iterable<E> {
  E? findFirst(bool Function(E) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

void _mergeFromProto3Json(
    Object? json,
    FieldSet fieldSet,
    TypeRegistry typeRegistry,
    bool ignoreUnknownFields,
    bool supportNamesWithUnderscores,
    bool permissiveEnums) {
  var context = JsonParsingContext(
      ignoreUnknownFields, supportNamesWithUnderscores, permissiveEnums);

  void recursionHelper(Object? json, FieldSet fieldSet) {
    int tryParse32Bit(String s) {
      return int.tryParse(s) ??
          (throw context.parseException('expected integer', s));
    }

    int check32BitSigned(int n) {
      if (n < -2147483648 || n > 2147483647) {
        throw context.parseException('expected 32 bit unsigned integer', n);
      }
      return n;
    }

    int check32BitUnsigned(int n) {
      if (n < 0 || n > 0xFFFFFFFF) {
        throw context.parseException('expected 32 bit unsigned integer', n);
      }
      return n;
    }

    Int64 tryParse64Bit(String s) {
      Int64 result;
      try {
        result = Int64.parseInt(s);
      } on FormatException {
        throw context.parseException('expected integer', json);
      }
      return result;
    }

    Object? convertProto3JsonValue(Object? value, FieldInfo fieldInfo) {
      if (value == null) {
        return fieldInfo.makeDefault!();
      }
      var fieldType = fieldInfo.type;
      switch (PbFieldType.baseType(fieldType)) {
        case PbFieldType.BOOL_BIT:
          if (value is bool) {
            return value;
          }
          throw context.parseException('Expected bool value', json);
        case PbFieldType.BYTES_BIT:
          if (value is String) {
            Uint8List result;
            try {
              result = base64Decode(value);
            } on FormatException {
              throw context.parseException(
                  'Expected bytes encoded as base64 String', json);
            }
            return result;
          }
          throw context.parseException(
              'Expected bytes encoded as base64 String', value);
        case PbFieldType.STRING_BIT:
          if (value is String) {
            return value;
          }
          throw context.parseException('Expected String value', value);
        case PbFieldType.FLOAT_BIT:
        case PbFieldType.DOUBLE_BIT:
          if (value is double) {
            return value;
          } else if (value is num) {
            return value.toDouble();
          } else if (value is String) {
            return double.tryParse(value) ??
                (throw context.parseException(
                    'Expected String to encode a double', value));
          }
          throw context.parseException(
              'Expected a double represented as a String or number', value);
        case PbFieldType.ENUM_BIT:
          if (value is String) {
            // TODO(sigurdm): Do we want to avoid linear search here? Measure...
            final result = permissiveEnums
                ? fieldInfo.enumValues!
                    .findFirst((e) => permissiveCompare(e.name, value))
                : fieldInfo.enumValues!.findFirst((e) => e.name == value);
            if ((result != null) || ignoreUnknownFields) return result;
            throw context.parseException('Unknown enum value', value);
          } else if (value is int) {
            return fieldInfo.valueOf!(value) ??
                (ignoreUnknownFields
                    ? null
                    : (throw context.parseException(
                        'Unknown enum value', value)));
          }
          throw context.parseException(
              'Expected enum as a string or integer', value);
        case PbFieldType.UINT32_BIT:
          int result;
          if (value is int) {
            result = value;
          } else if (value is String) {
            result = tryParse32Bit(value);
          } else {
            throw context.parseException(
                'Expected int or stringified int', value);
          }
          return check32BitUnsigned(result);
        case PbFieldType.INT32_BIT:
        case PbFieldType.SINT32_BIT:
        case PbFieldType.FIXED32_BIT:
        case PbFieldType.SFIXED32_BIT:
          int result;
          if (value is int) {
            result = value;
          } else if (value is String) {
            result = tryParse32Bit(value);
          } else {
            throw context.parseException(
                'Expected int or stringified int', value);
          }
          check32BitSigned(result);
          return result;
        case PbFieldType.UINT64_BIT:
          Int64 result;
          if (value is int) {
            result = Int64(value);
          } else if (value is String) {
            result = tryParse64Bit(value);
          } else {
            throw context.parseException(
                'Expected int or stringified int', value);
          }
          return result;
        case PbFieldType.INT64_BIT:
        case PbFieldType.SINT64_BIT:
        case PbFieldType.FIXED64_BIT:
        case PbFieldType.SFIXED64_BIT:
          if (value is int) return Int64(value);
          if (value is String) {
            Int64 result;
            try {
              result = Int64.parseInt(value);
            } on FormatException {
              throw context.parseException(
                  'Expected int or stringified int', value);
            }
            return result;
          }
          throw context.parseException(
              'Expected int or stringified int', value);
        case PbFieldType.GROUP_BIT:
        case PbFieldType.MESSAGE_BIT:
          var subMessage = fieldInfo.subBuilder!();
          recursionHelper(value, subMessage.fieldSet);
          return subMessage;
        default:
          throw StateError('Unknown type $fieldType');
      }
    }

    Object decodeMapKey(String key, int fieldType) {
      switch (PbFieldType.baseType(fieldType)) {
        case PbFieldType.BOOL_BIT:
          switch (key) {
            case 'true':
              return true;
            case 'false':
              return false;
            default:
              throw context.parseException(
                  'Wrong boolean key, should be one of ("true", "false")', key);
          }
          // ignore: dead_code
          throw StateError('(Should have been) unreachable statement');
        case PbFieldType.STRING_BIT:
          return key;
        case PbFieldType.UINT64_BIT:
          // TODO(sigurdm): We do not throw on negative values here.
          // That would probably require going via bignum.
          return tryParse64Bit(key);
        case PbFieldType.INT64_BIT:
        case PbFieldType.SINT64_BIT:
        case PbFieldType.SFIXED64_BIT:
        case PbFieldType.FIXED64_BIT:
          return tryParse64Bit(key);
        case PbFieldType.INT32_BIT:
        case PbFieldType.SINT32_BIT:
        case PbFieldType.FIXED32_BIT:
        case PbFieldType.SFIXED32_BIT:
          return check32BitSigned(tryParse32Bit(key));
        case PbFieldType.UINT32_BIT:
          return check32BitUnsigned(tryParse32Bit(key));
        default:
          throw StateError('Not a valid key type $fieldType');
      }
    }

    if (json == null) {
      // `null` represents the default value. Do nothing more.
      return;
    }

    final info = fieldSet.meta;
    final wellKnownConverter = info.fromProto3Json;
    if (wellKnownConverter != null) {
      wellKnownConverter(fieldSet._message!, json, typeRegistry, context);
    } else {
      if (json is Map) {
        final byName = info.byName;

        json.forEach((key, Object? value) {
          if (key is! String) {
            throw context.parseException('Key was not a String', key);
          }
          context.addMapIndex(key);

          var fieldInfo = byName[key];
          if (fieldInfo == null && supportNamesWithUnderscores) {
            // We don't optimize for field names with underscores, instead do a
            // linear search for the index.
            fieldInfo = byName.values
                .findFirst((FieldInfo info) => info.protoName == key);
          }
          if (fieldInfo == null) {
            if (ignoreUnknownFields) {
              return;
            } else {
              throw context.parseException('Unknown field name \'$key\'', key);
            }
          }

          if (isMapFieldType(fieldInfo.type)) {
            if (value is Map) {
              final mapFieldInfo = fieldInfo as MapFieldInfo<dynamic, dynamic>;
              final Map fieldValues = fieldSet.ensureMapField(info, fieldInfo);
              value.forEach((subKey, subValue) {
                if (subKey is! String) {
                  throw context.parseException('Expected a String key', subKey);
                }
                context.addMapIndex(subKey);
                fieldValues[decodeMapKey(subKey, mapFieldInfo.keyFieldType!)] =
                    convertProto3JsonValue(
                        subValue, mapFieldInfo.valueFieldInfo);
                context.popIndex();
              });
            } else {
              throw context.parseException('Expected a map', value);
            }
          } else if (isRepeatedFieldType(fieldInfo.type)) {
            if (value == null) {
              // `null` is accepted as the empty list [].
              fieldSet.ensureRepeatedField(info, fieldInfo);
            } else if (value is List) {
              var values = fieldSet.ensureRepeatedField(info, fieldInfo);
              for (var i = 0; i < value.length; i++) {
                final entry = value[i];
                context.addListIndex(i);
                values.add(convertProto3JsonValue(entry, fieldInfo));
                context.popIndex();
              }
            } else {
              throw context.parseException('Expected a list', value);
            }
          } else if (isGroupOrMessageFieldType(fieldInfo.type)) {
            // TODO(sigurdm) consider a cleaner separation between parsing and
            // merging.
            var parsedSubMessage =
                convertProto3JsonValue(value, fieldInfo) as GeneratedMessage;
            GeneratedMessage? original = fieldSet.values[fieldInfo.index!];
            if (original == null) {
              fieldSet._setNonExtensionFieldUnchecked(
                  info, fieldInfo, parsedSubMessage);
            } else {
              original.mergeFromMessage(parsedSubMessage);
            }
          } else {
            fieldSet.setFieldUnchecked(
                info, fieldInfo, convertProto3JsonValue(value, fieldInfo));
          }
          context.popIndex();
        });
      } else {
        throw context.parseException('Expected JSON object', json);
      }
    }
  }

  recursionHelper(json, fieldSet);
}
