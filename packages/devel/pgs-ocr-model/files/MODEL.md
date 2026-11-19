# PP-OCRv5 mobile recognition model

Source: https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx
Original SHA256: 5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5
License: Apache-2.0, https://github.com/PaddlePaddle/PaddleOCR/blob/v3.0.0/LICENSE

Dynamic quantization: ONNX Runtime quantize_dynamic, per_channel=True,
weight_type=QInt8, op_types_to_quantize=["MatMul", "Gemm"]. Conv weights remain FP32.
Result: 9,429,126 bytes, SHA256
2157a3afca502e6fc23e4679de4e46c9e855247bcda645c8faa02c9e5bd011c1.
Character dictionary is embedded in ONNX metadata. No runtime downloads.
Original setup script provenance is recorded in the R10 PGS identification task.
