// Copyright 2021 The gVisor Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package tcpip

import (
	"fmt"
)

// Error represents an error in the netstack error space.
//
// The error interface is intentionally omitted to avoid loss of type
// information that would occur if these errors were passed as error.
type Error interface {
	isError()

	// IgnoreStats indicates whether this error should be included in failure
	// counts in tcpip.Stats structs.
	IgnoreStats() bool

	fmt.Stringer
}

// ErrBadAddress indicates a bad address was provided.
//
// +stateify savable
type ErrBadAddress struct{}

func (*ErrBadAddress) isError() {}

// IgnoreStats implements Error.
func (*ErrBadAddress) IgnoreStats() bool {
	return false
}
func (*ErrBadAddress) String() string { return "bad address" }
