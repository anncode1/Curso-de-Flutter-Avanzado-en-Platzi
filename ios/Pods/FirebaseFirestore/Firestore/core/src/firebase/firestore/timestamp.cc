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

#include "Firestore/core/include/firebase/firestore/timestamp.h"

#include <ostream>

#include "Firestore/core/src/firebase/firestore/util/hard_assert.h"
#include "absl/strings/str_cat.h"

namespace firebase {

Timestamp::Timestamp() {
}

Timestamp::Timestamp(const int64_t seconds, const int32_t nanoseconds)
    : seconds_(seconds), nanoseconds_(nanoseconds) {
  ValidateBounds();
}

Timestamp Timestamp::Now() {
#if !defined(_STLPORT_VERSION)
  // Use the standard <chrono> library from C++11 if possible.
  return FromTimePoint(std::chrono::system_clock::now());
#else
  // If <chrono> is unavailable, use clock_gettime from POSIX, which supports up
  // to nanosecond resolution. Note that it's a non-standard function contained
  // in <time.h>.
  //
  // Note: it's possible to check for availability of POSIX clock_gettime using
  // macros (see "Availability" at https://linux.die.net/man/3/clock_gettime).
  // However, the only platform where <chrono> isn't available is Android with
  // STLPort standard library, where clock_gettime is known to be available.
  timespec now;
  clock_gettime(CLOCK_REALTIME, &now);
  return Timestamp(now.tv_sec, now.tv_nsec);
#endif  // !defined(_STLPORT_VERSION)
}

Timestamp Timestamp::FromTimeT(const time_t seconds_since_unix_epoch) {
  return {seconds_since_unix_epoch, 0};
}

#if !defined(_STLPORT_VERSION)
Timestamp Timestamp::FromTimePoint(
    const std::chrono::time_point<std::chrono::system_clock> time_point) {
  namespace chr = std::chrono;
  const auto epoch_time = time_point.time_since_epoch();
  auto seconds = chr::duration_cast<chr::duration<int64_t>>(epoch_time);
  auto nanoseconds = chr::duration_cast<chr::nanoseconds>(epoch_time - seconds);
  HARD_ASSERT(nanoseconds.count() < 1 * 1000 * 1000 * 1000);

  if (nanoseconds.count() < 0) {
    // Timestamp format always has a positive number of nanoseconds that is
    // counting forward. For negative time, we need to transform chrono
    // representation of (negative seconds s1 + negative nanoseconds ns1) to
    // (negative seconds s2 + positive nanoseconds ns2). Since nanosecond part
    // is always less than 1 second in our representation, instead of starting
    // at s1 and going back ns1 nanoseconds, start at (s1 minus one second) and
    // go *forward* ns2 = (1 second + ns1, ns1 < 0) nanoseconds.
    //
    // Note: if nanoseconds are negative, it must mean that seconds are
    // non-positive, but the formula would still be valid, so no need to check.
    seconds = seconds - chr::seconds(1);
    nanoseconds = chr::seconds(1) + nanoseconds;
  }

  const Timestamp result{seconds.count(),
                         static_cast<int32_t>(nanoseconds.count())};
  result.ValidateBounds();
  return result;
}

#endif  // !defined(_STLPORT_VERSION)

std::string Timestamp::ToString() const {
  return absl::StrCat("Timestamp(seconds=", seconds_,
                      ", nanoseconds=", nanoseconds_, ")");
}

std::ostream& operator<<(std::ostream& out, const Timestamp& timestamp) {
  return out << timestamp.ToString();
}

void Timestamp::ValidateBounds() const {
  HARD_ASSERT(nanoseconds_ >= 0, "Timestamp nanoseconds out of range: %s",
              nanoseconds_);
  HARD_ASSERT(nanoseconds_ < 1e9, "Timestamp nanoseconds out of range: %s",
              nanoseconds_);
  // Midnight at the beginning of 1/1/1 is the earliest timestamp Firestore
  // supports.
  HARD_ASSERT(seconds_ >= -62135596800L, "Timestamp seconds out of range: %s",
              seconds_);
  // This will break in the year 10,000.
  HARD_ASSERT(seconds_ < 253402300800L, "Timestamp seconds out of range: %s",
              seconds_);
}

}  // namespace firebase

namespace std {
size_t hash<firebase::Timestamp>::operator()(
    const firebase::Timestamp& timestamp) const {
  // Note: if sizeof(size_t) == 4, this discards high-order bits of seconds.
  return 37 * static_cast<size_t>(timestamp.seconds()) +
         static_cast<size_t>(timestamp.nanoseconds());
}

}  // namespace std
