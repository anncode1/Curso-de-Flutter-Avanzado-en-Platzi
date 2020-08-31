/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "Firestore/core/src/firebase/firestore/model/field_value.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <new>
#include <utility>
#include <vector>

#include "Firestore/core/src/firebase/firestore/immutable/sorted_map.h"
#include "Firestore/core/src/firebase/firestore/util/comparison.h"
#include "Firestore/core/src/firebase/firestore/util/hard_assert.h"
#include "absl/memory/memory.h"

using firebase::firestore::util::Comparator;

namespace firebase {
namespace firestore {
namespace model {

using Type = FieldValue::Type;
using firebase::firestore::util::ComparisonResult;

FieldValue::FieldValue(const FieldValue& value) {
  *this = value;
}

FieldValue::FieldValue(FieldValue&& value) {
  *this = std::move(value);
}

FieldValue::~FieldValue() {
  SwitchTo(Type::Null);
}

FieldValue& FieldValue::operator=(const FieldValue& value) {
  SwitchTo(value.tag_);
  switch (tag_) {
    case Type::Null:
      break;
    case Type::Boolean:
      boolean_value_ = value.boolean_value_;
      break;
    case Type::Integer:
      integer_value_ = value.integer_value_;
      break;
    case Type::Double:
      double_value_ = value.double_value_;
      break;
    case Type::Timestamp:
      *timestamp_value_ = *value.timestamp_value_;
      break;
    case Type::ServerTimestamp:
      *server_timestamp_value_ = *value.server_timestamp_value_;
      break;
    case Type::String:
      *string_value_ = *value.string_value_;
      break;
    case Type::Blob: {
      // copy-and-swap
      std::vector<uint8_t> tmp = *value.blob_value_;
      std::swap(*blob_value_, tmp);
      break;
    }
    case Type::Reference:
      *reference_value_ = *value.reference_value_;
      break;
    case Type::GeoPoint:
      *geo_point_value_ = *value.geo_point_value_;
      break;
    case Type::Array: {
      // copy-and-swap
      std::vector<FieldValue> tmp = *value.array_value_;
      std::swap(*array_value_, tmp);
      break;
    }
    case Type::Object: {
      // copy-and-swap
      Map tmp = *value.object_value_;
      std::swap(*object_value_, tmp);
      break;
    }
    default:
      HARD_FAIL("Unsupported type %s", value.type());
  }
  return *this;
}

FieldValue& FieldValue::operator=(FieldValue&& value) {
  switch (value.tag_) {
    case Type::String:
      SwitchTo(Type::String);
      string_value_->swap(*value.string_value_);
      return *this;
    case Type::Blob:
      SwitchTo(Type::Blob);
      std::swap(blob_value_, value.blob_value_);
      return *this;
    case Type::Reference:
      SwitchTo(Type::Reference);
      std::swap(reference_value_, value.reference_value_);
      return *this;
    case Type::Array:
      SwitchTo(Type::Array);
      std::swap(array_value_, value.array_value_);
      return *this;
    case Type::Object:
      SwitchTo(Type::Object);
      std::swap(object_value_, value.object_value_);
      return *this;
    default:
      // We just copy over POD union types.
      *this = value;
      return *this;
  }
}

bool FieldValue::Comparable(Type lhs, Type rhs) {
  switch (lhs) {
    case Type::Integer:
    case Type::Double:
      return rhs == Type::Integer || rhs == Type::Double;
    case Type::Timestamp:
    case Type::ServerTimestamp:
      return rhs == Type::Timestamp || rhs == Type::ServerTimestamp;
    default:
      return lhs == rhs;
  }
}

// TODO(rsgowman): Reorder this file to match its header.
ObjectValue ObjectValue::Set(const FieldPath& field_path,
                             const FieldValue& value) const {
  HARD_ASSERT(!field_path.empty(),
              "Cannot set field for empty path on FieldValue");
  // Set the value by recursively calling on child object.
  const std::string& child_name = field_path.first_segment();
  if (field_path.size() == 1) {
    return SetChild(child_name, value);
  } else {
    ObjectValue child = ObjectValue::Empty();
    const auto iter = fv_.object_value_->find(child_name);
    if (iter != fv_.object_value_->end() &&
        iter->second.type() == Type::Object) {
      child = ObjectValue(iter->second);
    }
    ObjectValue new_child = child.Set(field_path.PopFirst(), value);
    return SetChild(child_name, new_child.fv_);
  }
}

ObjectValue ObjectValue::Delete(const FieldPath& field_path) const {
  HARD_ASSERT(!field_path.empty(),
              "Cannot delete field for empty path on FieldValue");
  // Delete the value by recursively calling on child object.
  const std::string& child_name = field_path.first_segment();
  if (field_path.size() == 1) {
    return ObjectValue::FromMap(fv_.object_value_->erase(child_name));
  } else {
    const auto iter = fv_.object_value_->find(child_name);
    if (iter != fv_.object_value_->end() &&
        iter->second.type() == Type::Object) {
      ObjectValue new_child =
          ObjectValue(iter->second).Delete(field_path.PopFirst());
      return SetChild(child_name, new_child.fv_);
    } else {
      // If the found value isn't an object, it cannot contain the remaining
      // segments of the path. We don't actually change a primitive value to
      // an object for a delete.
      return *this;
    }
  }
}

absl::optional<FieldValue> ObjectValue::Get(const FieldPath& field_path) const {
  const FieldValue* current = &this->fv_;
  for (const auto& path : field_path) {
    if (current->type() != Type::Object) {
      return absl::nullopt;
    }
    const auto iter = current->object_value_->find(path);
    if (iter == current->object_value_->end()) {
      return absl::nullopt;
    } else {
      current = &iter->second;
    }
  }
  return *current;
}

ObjectValue ObjectValue::SetChild(const std::string& child_name,
                                  const FieldValue& value) const {
  return ObjectValue::FromMap(fv_.object_value_->insert(child_name, value));
}

FieldValue FieldValue::Null() {
  return FieldValue();
}

FieldValue FieldValue::True() {
  return FieldValue(true);
}

FieldValue FieldValue::False() {
  return FieldValue(false);
}

FieldValue FieldValue::FromBoolean(bool value) {
  return value ? True() : False();
}

FieldValue FieldValue::Nan() {
  return FieldValue::FromDouble(NAN);
}

FieldValue FieldValue::EmptyObject() {
  return FieldValue::FromMap(FieldValue::Map());
}

FieldValue FieldValue::FromInteger(int64_t value) {
  FieldValue result;
  result.SwitchTo(Type::Integer);
  result.integer_value_ = value;
  return result;
}

FieldValue FieldValue::FromDouble(double value) {
  FieldValue result;
  result.SwitchTo(Type::Double);
  result.double_value_ = value;
  return result;
}

FieldValue FieldValue::FromTimestamp(const Timestamp& value) {
  FieldValue result;
  result.SwitchTo(Type::Timestamp);
  *result.timestamp_value_ = value;
  return result;
}

FieldValue FieldValue::FromServerTimestamp(const Timestamp& local_write_time,
                                           const Timestamp& previous_value) {
  FieldValue result;
  result.SwitchTo(Type::ServerTimestamp);
  result.server_timestamp_value_->local_write_time = local_write_time;
  result.server_timestamp_value_->previous_value = previous_value;
  return result;
}

FieldValue FieldValue::FromServerTimestamp(const Timestamp& local_write_time) {
  FieldValue result;
  result.SwitchTo(Type::ServerTimestamp);
  result.server_timestamp_value_->local_write_time = local_write_time;
  result.server_timestamp_value_->previous_value = absl::nullopt;
  return result;
}

FieldValue FieldValue::FromString(const char* value) {
  std::string copy(value);
  return FromString(std::move(copy));
}

FieldValue FieldValue::FromString(const std::string& value) {
  std::string copy(value);
  return FromString(std::move(copy));
}

FieldValue FieldValue::FromString(std::string&& value) {
  FieldValue result;
  result.SwitchTo(Type::String);
  result.string_value_->swap(value);
  return result;
}

FieldValue FieldValue::FromBlob(const uint8_t* source, size_t size) {
  FieldValue result;
  result.SwitchTo(Type::Blob);
  std::vector<uint8_t> copy(source, source + size);
  std::swap(*result.blob_value_, copy);
  return result;
}

// Does NOT pass ownership of database_id.
FieldValue FieldValue::FromReference(const DocumentKey& value,
                                     const DatabaseId* database_id) {
  FieldValue result;
  result.SwitchTo(Type::Reference);
  result.reference_value_->reference = value;
  result.reference_value_->database_id = database_id;
  return result;
}

// Does NOT pass ownership of database_id.
FieldValue FieldValue::FromReference(DocumentKey&& value,
                                     const DatabaseId* database_id) {
  FieldValue result;
  result.SwitchTo(Type::Reference);
  std::swap(result.reference_value_->reference, value);
  result.reference_value_->database_id = database_id;
  return result;
}

FieldValue FieldValue::FromGeoPoint(const GeoPoint& value) {
  FieldValue result;
  result.SwitchTo(Type::GeoPoint);
  *result.geo_point_value_ = value;
  return result;
}

FieldValue FieldValue::FromArray(const std::vector<FieldValue>& value) {
  std::vector<FieldValue> copy(value);
  return FromArray(std::move(copy));
}

FieldValue FieldValue::FromArray(std::vector<FieldValue>&& value) {
  FieldValue result;
  result.SwitchTo(Type::Array);
  std::swap(*result.array_value_, value);
  return result;
}

FieldValue FieldValue::FromMap(const FieldValue::Map& value) {
  FieldValue::Map copy(value);
  return FromMap(std::move(copy));
}

FieldValue FieldValue::FromMap(FieldValue::Map&& value) {
  FieldValue result;
  result.SwitchTo(Type::Object);
  std::swap(*result.object_value_, value);
  return result;
}

bool operator<(const FieldValue::Map& lhs, const FieldValue::Map& rhs) {
  return std::lexicographical_compare(lhs.begin(), lhs.end(), rhs.begin(),
                                      rhs.end());
}

bool operator<(const FieldValue& lhs, const FieldValue& rhs) {
  if (!FieldValue::Comparable(lhs.type(), rhs.type())) {
    return lhs.type() < rhs.type();
  }

  switch (lhs.type()) {
    case Type::Null:
      return false;
    case Type::Boolean:
      return Comparator<bool>()(lhs.boolean_value_, rhs.boolean_value_);
    case Type::Integer:
      if (rhs.type() == Type::Integer) {
        return Comparator<int64_t>()(lhs.integer_value_, rhs.integer_value_);
      } else {
        return util::CompareMixedNumber(rhs.double_value_,
                                        lhs.integer_value_) ==
               ComparisonResult::Descending;
      }
    case Type::Double:
      if (rhs.type() == Type::Double) {
        return Comparator<double>()(lhs.double_value_, rhs.double_value_);
      } else {
        return util::CompareMixedNumber(lhs.double_value_,
                                        rhs.integer_value_) ==
               ComparisonResult::Ascending;
      }
    case Type::Timestamp:
      if (rhs.type() == Type::Timestamp) {
        return *lhs.timestamp_value_ < *rhs.timestamp_value_;
      } else {
        return true;
      }
    case Type::ServerTimestamp:
      if (rhs.type() == Type::ServerTimestamp) {
        return lhs.server_timestamp_value_->local_write_time <
               rhs.server_timestamp_value_->local_write_time;
      } else {
        return false;
      }
    case Type::String:
      return lhs.string_value_->compare(*rhs.string_value_) < 0;
    case Type::Blob:
      return *lhs.blob_value_ < *rhs.blob_value_;
    case Type::Reference:
      return *lhs.reference_value_->database_id <
                 *rhs.reference_value_->database_id ||
             (*lhs.reference_value_->database_id ==
                  *rhs.reference_value_->database_id &&
              lhs.reference_value_->reference <
                  rhs.reference_value_->reference);
    case Type::GeoPoint:
      return *lhs.geo_point_value_ < *rhs.geo_point_value_;
    case Type::Array:
      return *lhs.array_value_ < *rhs.array_value_;
    case Type::Object:
      return *lhs.object_value_ < *rhs.object_value_;
    default:
      HARD_FAIL("Unsupported type %s", lhs.type());
      // return false if assertion does not abort the program. We will say
      // each unsupported type takes only one value thus everything is equal.
      return false;
  }
}

void FieldValue::SwitchTo(const Type type) {
  if (tag_ == type) {
    return;
  }
  // Not same type. Destruct old type first and then initialize new type.
  // Must call destructor explicitly for any non-POD type.
  switch (tag_) {
    case Type::Timestamp:
      timestamp_value_.~unique_ptr<Timestamp>();
      break;
    case Type::ServerTimestamp:
      server_timestamp_value_.~unique_ptr<ServerTimestamp>();
      break;
    case Type::String:
      string_value_.~unique_ptr<std::string>();
      break;
    case Type::Blob:
      blob_value_.~unique_ptr<std::vector<uint8_t>>();
      break;
    case Type::Reference:
      reference_value_.~unique_ptr<ReferenceValue>();
      break;
    case Type::GeoPoint:
      geo_point_value_.~unique_ptr<GeoPoint>();
      break;
    case Type::Array:
      array_value_.~unique_ptr<std::vector<FieldValue>>();
      break;
    case Type::Object:
      object_value_.~unique_ptr<Map>();
      break;
    default: {}  // The other types where there is nothing to worry about.
  }
  tag_ = type;
  // Must call constructor explicitly for any non-POD type to initialize.
  switch (tag_) {
    case Type::Timestamp:
      new (&timestamp_value_)
          std::unique_ptr<Timestamp>(absl::make_unique<Timestamp>(0, 0));
      break;
    case Type::ServerTimestamp:
      new (&server_timestamp_value_) std::unique_ptr<ServerTimestamp>(
          absl::make_unique<ServerTimestamp>());
      break;
    case Type::String:
      new (&string_value_)
          std::unique_ptr<std::string>(absl::make_unique<std::string>());
      break;
    case Type::Blob:
      // Do not even bother to allocate a new array of size 0.
      new (&blob_value_) std::unique_ptr<std::vector<uint8_t>>(
          absl::make_unique<std::vector<uint8_t>>());
      break;
    case Type::Reference:
      new (&reference_value_)
          std::unique_ptr<ReferenceValue>(absl::make_unique<ReferenceValue>());
      break;
    case Type::GeoPoint:
      new (&geo_point_value_)
          std::unique_ptr<GeoPoint>(absl::make_unique<GeoPoint>());
      break;
    case Type::Array:
      new (&array_value_) std::unique_ptr<std::vector<FieldValue>>(
          absl::make_unique<std::vector<FieldValue>>());
      break;
    case Type::Object:
      new (&object_value_) std::unique_ptr<Map>(absl::make_unique<Map>());
      break;
    default: {}  // The other types where there is nothing to worry about.
  }
}

ObjectValue ObjectValue::FromMap(const FieldValue::Map& value) {
  return ObjectValue(FieldValue::FromMap(value));
}

ObjectValue ObjectValue::FromMap(FieldValue::Map&& value) {
  return ObjectValue(FieldValue::FromMap(std::move(value)));
}

}  // namespace model
}  // namespace firestore
}  // namespace firebase
