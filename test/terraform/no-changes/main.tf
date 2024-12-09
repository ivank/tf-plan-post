resource "local_file" "foo" {
  content  = var.foo_content
  filename = "${path.module}/foo.bar"
}
