## 2024-05-18 - Swift Array Containment Check N+1 Optimization
**Learning:** In a `for ... where !array.contains(...)` loop, the array is linearly searched for each iteration, resulting in O(N*M) algorithmic complexity. This causes severe performance degradation when iterating over large datasets or parsing many paths.
**Action:** When filtering against large collections inside loops, always pre-convert the filter array into a `Set` outside the loop to ensure O(1) containment checks, improving overall complexity to O(N+M).
