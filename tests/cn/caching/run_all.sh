#!/bin/bash

echo "========================================="
echo "CN Incremental Verification Test Suite"
echo "========================================="
echo

for test_dir in spec_change body_change predicate_change logical_function_change comment_change argument_rename transitive_predicate function_call logical_function lemma struct_change datatype_change broken_implementation cached_failure predicate_uses_logical_function predicate_uses_struct predicate_uses_datatype logical_function_recursive logical_function_uses_struct logical_function_uses_datatype lemma_uses_logical_function lemma_uses_struct lemma_uses_datatype; do
  echo
  echo "========================================="
  cd "$test_dir"
  bash run.sh
  cd ..
  echo "========================================="
done

echo
echo "All tests completed!"
