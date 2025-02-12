// RUN: tf-tfrt-opt %s --tf-cpurt-pad-tiled-ops | FileCheck %s

func @reduce(%in: tensor<?x?xf32>) -> tensor<?xf32> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %cst = arith.constant 0.000000e+00 : f32

  %0 = tensor.dim %in, %c0 : tensor<?x?xf32>
  %undef = linalg.init_tensor [%0] : tensor<?xf32>
  %clone = linalg.init_tensor [%0] : tensor<?xf32>
  %out = linalg.fill(%cst, %undef) : f32, tensor<?xf32> -> tensor<?xf32>
  %3 = tensor.dim %in, %c0 : tensor<?x?xf32>
  %4 = tensor.dim %in, %c1 : tensor<?x?xf32>
  %result:2 = linalg.tiled_loop (%i, %j) = (%c0, %c0) to (%3, %4) step (%c4, %c4)
           ins (%in_ = %in: tensor<?x?xf32>)
           outs (%out_ = %out: tensor<?xf32>, %clone_ = %clone: tensor<?xf32>)
           iterators["parallel", "reduction"] {
    %6 = tensor.dim %in_, %c0 : tensor<?x?xf32>
    %7 = affine.min affine_map<(d0)[s0] -> (4, -d0 + s0)>(%i)[%6]
    %8 = tensor.dim %in_, %c1 : tensor<?x?xf32>
    %9 = affine.min affine_map<(d0)[s0] -> (4, -d0 + s0)>(%j)[%8]
    %11 = tensor.dim %out_, %c0 : tensor<?xf32>
    %12 = affine.min affine_map<(d0)[s0] -> (4, -d0 + s0)>(%i)[%11]
    %13 = tensor.dim %out_, %c0 : tensor<?xf32>
    %14 = affine.min 
            affine_map<(d0, d1)[s0] -> (d0 - d1, 4, -d1 + s0)>(%13, %i)[%11]

    %in_sub = tensor.extract_slice %in_[%i, %j] [%7, %9] [1, 1]
            : tensor<?x?xf32> to tensor<?x?xf32>
    %out_sub = tensor.extract_slice %out_[%i] [%14] [1]
            : tensor<?xf32> to tensor<?xf32>
    %clone_sub = tensor.extract_slice %clone_[%i] [%14] [1]
            : tensor<?xf32> to tensor<?xf32>
    %init_tmp_result = linalg.fill(%cst, %clone_sub)
            : f32, tensor<?xf32> -> tensor<?xf32>
    %tmp_result = linalg.generic {
            indexing_maps = [affine_map<(d0, d1) -> (d0, d1)>,
                             affine_map<(d0, d1) -> (d0)>],
            iterator_types = ["parallel", "reduction"]}
            ins(%in_sub : tensor<?x?xf32>)
            outs(%init_tmp_result : tensor<?xf32>) {
    ^bb0(%arg6: f32, %arg7: f32):
      %20 = arith.addf %arg6, %arg7 : f32
      linalg.yield %20 : f32
    } -> tensor<?xf32>
    %updated_out_sub = linalg.generic {
            indexing_maps = [affine_map<(d0) -> (d0)>,
                             affine_map<(d0) -> (d0)>],
            iterator_types = ["parallel"]}
            ins(%tmp_result : tensor<?xf32>)
            outs(%out_sub : tensor<?xf32>) {
    ^bb0(%arg6: f32, %arg7: f32):
      %20 = arith.addf %arg6, %arg7 : f32
      linalg.yield %20 : f32
    } -> tensor<?xf32>
    %insert_out = tensor.insert_slice %updated_out_sub into %out_[%i] [%12] [1]
        : tensor<?xf32> into tensor<?xf32>
    %insert_clone = tensor.insert_slice %tmp_result into %clone_[%i] [%12] [1]
        : tensor<?xf32> into tensor<?xf32>
    linalg.yield %insert_out, %insert_clone : tensor<?xf32>, tensor<?xf32>
  }
  return %result#0 : tensor<?xf32>
}

// CHECK-LABEL: reduce

// CHECK: linalg.tiled_loop
// CHECK-SAME: ins (%[[IN:arg[0-9]]] = %{{.*}}: tensor<?x?xf32>)
// CHECK-SAME: outs (%[[OUT:arg[0-9]]] = %{{.*}}: tensor<?xf32>,
// CHECK-SAME:       %[[CLONE:arg[0-9]]] = %{{.*}}: tensor<?xf32>)

// CHECK: %[[IN_SUB:.*]] = tensor.extract_slice %[[IN]]
// CHECK: %[[OUT_SUB:.*]] = tensor.extract_slice %[[OUT]]
// CHECK: %[[CLONE_SUB:.*]] = tensor.extract_slice %[[CLONE]]

// CHECK: %[[CLONE_PAD:.*]] = linalg.pad_tensor %[[CLONE_SUB]]
// CHECK: %[[INIT:.*]] = linalg.fill(%{{.*}}, %[[CLONE_PAD]])

// CHECK: %[[IN_PAD:.*]] = linalg.pad_tensor %[[IN_SUB]]

// CHECK: %[[TMP:.*]] = linalg.generic
// CHECK-SAME: ins(%[[IN_PAD]] : tensor<4x4xf32>) outs(%[[INIT]] : tensor<4xf32>)

// CHECK: %[[OUT_PAD:.*]] = linalg.pad_tensor %[[OUT_SUB]]
// CHECK: %[[UPDATED_OUT_SUB:.*]] = linalg.generic
// CHECK-SAME: ins(%[[TMP]] : tensor<4xf32>) outs(%[[OUT_PAD]] : tensor<4xf32>)

// CHECK: %[[SLICE:.*]] = tensor.extract_slice %[[UPDATED_OUT_SUB]]
// CHECK: %[[INSERT_OUT:.*]] = tensor.insert_slice %[[SLICE]] into %[[OUT]]
