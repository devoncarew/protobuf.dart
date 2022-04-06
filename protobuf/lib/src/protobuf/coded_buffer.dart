// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protobuf;

void _writeToCodedBufferWriter(_FieldSet fs, CodedBufferWriter out) {
  // Sorting by tag number isn't required, but it sometimes enables
  // performance optimizations for the receiver. See:
  // https://developers.google.com/protocol-buffers/docs/encoding?hl=en#order

  for (var fi in fs._infosSortedByTag) {
    var value = fs._values[fi.index!];
    if (value == null) continue;
    out.writeField(fi.tagNumber, fi.type, value);
  }

  if (fs._hasExtensions) {
    for (var tagNumber in _sorted(fs._extensions!._tagNumbers)) {
      var fi = fs._extensions!._getInfoOrNull(tagNumber)!;
      out.writeField(tagNumber, fi.type, fs._extensions!._getFieldOrNull(fi));
    }
  }
  if (fs._hasUnknownFields) {
    fs._unknownFields!.writeToCodedBufferWriter(out);
  }
}

void _mergeFromCodedBufferReader(BuilderInfo meta, _FieldSet fs,
    CodedBufferReader input, ExtensionRegistry registry) {
  ArgumentError.checkNotNull(registry);
  while (true) {
    var tag = input.readTag();
    if (tag == 0) return;
    var wireType = tag & 0x7;
    var tagNumber = tag >> 3;

    var fi = fs._nonExtensionInfo(meta, tagNumber);
    fi ??= registry.getExtension(meta.qualifiedMessageName, tagNumber);

    if (fi == null || !_wireTypeMatches(fi.type, wireType)) {
      if (!fs._ensureUnknownFields().mergeFieldFromBuffer(tag, input)) {
        return;
      }
      continue;
    }

    // Ignore required/optional packed/unpacked.
    final fieldType = FieldTypeDetails(fi.type);

    switch (fieldType.baseType) {
      case BaseFieldType.bool:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readBool);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readBool());
        }
        break;

      case BaseFieldType.bytes:
        if (fieldType.isRepeated) {
          fs._ensureRepeatedField(meta, fi).add(input.readBytes());
        } else {
          fs._setFieldUnchecked(meta, fi, input.readBytes());
        }
        break;

      case BaseFieldType.string:
        if (fieldType.isRepeated) {
          fs._ensureRepeatedField(meta, fi).add(input.readString());
        } else {
          fs._setFieldUnchecked(meta, fi, input.readString());
        }
        break;

      case BaseFieldType.double:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readDouble);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readDouble());
        }
        break;

      case BaseFieldType.float:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readFloat);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readFloat());
        }
        break;

      case BaseFieldType.enum_:
        if (fieldType.isRepeated) {
          _readPackableToListEnum(
              meta, fs, input, wireType, fi, tagNumber, registry);
        } else {
          var rawValue = input.readEnum();
          var value = meta._decodeEnum(tagNumber, registry, rawValue);
          if (value == null) {
            var unknown = fs._ensureUnknownFields();
            unknown.mergeVarintField(tagNumber, Int64(rawValue));
          } else {
            fs._setFieldUnchecked(meta, fi, value);
          }
        }
        break;

      case BaseFieldType.int32:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readInt32);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readInt32());
        }
        break;

      case BaseFieldType.int64:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readInt64);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readInt64());
        }
        break;

      case BaseFieldType.sint32:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readSint32);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readSint32());
        }
        break;

      case BaseFieldType.sint64:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readSint64);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readSint64());
        }
        break;

      case BaseFieldType.uint32:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readUint32);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readUint32());
        }
        break;

      case BaseFieldType.uint64:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readUint64);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readUint64());
        }
        break;

      case BaseFieldType.fixed32:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readFixed32);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readFixed32());
        }
        break;

      case BaseFieldType.fixed64:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readFixed64);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readFixed64());
        }
        break;

      case BaseFieldType.sfixed32:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readSfixed32);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readSfixed32());
        }
        break;

      case BaseFieldType.sfixed64:
        if (fieldType.isRepeated) {
          _readPackable(meta, fs, input, wireType, fi, input.readSfixed64);
        } else {
          fs._setFieldUnchecked(meta, fi, input.readSfixed64());
        }
        break;

      case BaseFieldType.message:
        if (fieldType.isRepeated) {
          var subMessage = meta._makeEmptyMessage(tagNumber, registry);
          input.readMessage(subMessage, registry);
          fs._ensureRepeatedField(meta, fi).add(subMessage);
        } else {
          var subMessage = meta._makeEmptyMessage(tagNumber, registry);
          var oldValue = fs._getFieldOrNull(fi);
          if (oldValue != null) {
            subMessage.mergeFromMessage(oldValue);
          }
          input.readMessage(subMessage, registry);
          fs._setFieldUnchecked(meta, fi, subMessage);
        }
        break;

      case BaseFieldType.map:
        final mapFieldInfo = fi as MapFieldInfo;
        final mapEntryMeta = mapFieldInfo.mapEntryBuilderInfo;
        fs
            ._ensureMapField(meta, mapFieldInfo)
            ._mergeEntry(mapEntryMeta, input, registry);
        break;

      case BaseFieldType.group:
        if (fieldType.isRepeated) {
          var subMessage = meta._makeEmptyMessage(tagNumber, registry);
          input.readGroup(tagNumber, subMessage, registry);
          fs._ensureRepeatedField(meta, fi).add(subMessage);
        } else {
          var subMessage = meta._makeEmptyMessage(tagNumber, registry);
          var oldValue = fs._getFieldOrNull(fi);
          if (oldValue != null) {
            subMessage.mergeFromMessage(oldValue);
          }
          input.readGroup(tagNumber, subMessage, registry);
          fs._setFieldUnchecked(meta, fi, subMessage);
        }
        break;
    }
  }
}

void _readPackable(BuilderInfo meta, _FieldSet fs, CodedBufferReader input,
    int wireType, FieldInfo fi, Function readFunc) {
  void readToList(List list) => list.add(readFunc());
  _readPackableToList(meta, fs, input, wireType, fi, readToList);
}

void _readPackableToListEnum(
    BuilderInfo meta,
    _FieldSet fs,
    CodedBufferReader input,
    int wireType,
    FieldInfo fi,
    int tagNumber,
    ExtensionRegistry registry) {
  void readToList(List list) {
    var rawValue = input.readEnum();
    var value = meta._decodeEnum(tagNumber, registry, rawValue);
    if (value == null) {
      var unknown = fs._ensureUnknownFields();
      unknown.mergeVarintField(tagNumber, Int64(rawValue));
    } else {
      list.add(value);
    }
  }

  _readPackableToList(meta, fs, input, wireType, fi, readToList);
}

void _readPackableToList(BuilderInfo meta, _FieldSet fs,
    CodedBufferReader input, int wireType, FieldInfo fi, Function readToList) {
  var list = fs._ensureRepeatedField(meta, fi);

  if (wireType == WIRETYPE_LENGTH_DELIMITED) {
    // Packed.
    input._withLimit(input.readInt32(), () {
      while (!input.isAtEnd()) {
        readToList(list);
      }
    });
  } else {
    // Not packed.
    readToList(list);
  }
}
