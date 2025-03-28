import os

from ramalama.common import MNT_CHAT_TEMPLATE_FILE, MNT_DIR, MNT_FILE, get_accel_env_vars


class Quadlet:
    def __init__(self, model, chat_template, image, args, exec_args):
        self.ai_image = model
        if hasattr(args, "MODEL"):
            self.ai_image = args.MODEL
        self.ai_image = self.ai_image.removeprefix("oci://")
        if args.name:
            self.name = args.name
        else:
            self.name = os.path.basename(self.ai_image)

        self.model = model.removeprefix("oci://")
        self.args = args
        self.exec_args = exec_args
        self.image = image
        self.chat_template = chat_template

    def kube(self):
        outfile = self.name + ".kube"
        print(f"Generating quadlet file: {outfile}")
        with open(outfile, 'w') as c:
            c.write(
                f"""\
[Unit]
Description=RamaLama {self.model} Kubernetes YAML - AI Model Service
After=local-fs.target

[Kube]
Yaml={self.name}.yaml

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
"""
            )

    def generate(self):
        port_string = ""
        if hasattr(self.args, "port"):
            port_string = f"PublishPort={self.args.port}"

        name_string = ""
        if hasattr(self.args, "name") and self.args.name:
            name_string = f"ContainerName={self.args.name}"

        env_var_string = ""
        for k, v in get_accel_env_vars().items():
            env_var_string += f"Environment={k}={v}\n"

        outfile = self.name + ".container"
        print(f"Generating quadlet file: {outfile}")
        model_volume = self.gen_model_volume()
        chat_template_volume = self.gen_chat_template_volume()
        with open(outfile, 'w') as c:
            c.write(
                f"""\
[Unit]
Description=RamaLama {self.model} AI Model Service
After=local-fs.target

[Container]
AddDevice=-/dev/dri
AddDevice=-/dev/kfd
Exec={" ".join(self.exec_args)}
Image={self.image}
{env_var_string}
{model_volume}
{chat_template_volume}
{name_string}
{port_string}

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
"""
            )

    def gen_chat_template_volume(self):
        if os.path.exists(self.chat_template):
            return f"Mount=type=bind,src={self.chat_template},target={MNT_CHAT_TEMPLATE_FILE},ro,Z"
        return ""

    def gen_model_volume(self):
        if os.path.exists(self.model):
            return f"Mount=type=bind,src={self.model},target={MNT_FILE},ro,Z"

        outfile = self.name + ".volume"

        self.gen_image()
        print(f"Generating quadlet file: {outfile} ")
        with open(outfile, 'w') as c:
            c.write(
                f"""\
[Volume]
Driver=image
Image={self.name}.image
"""
            )
            return f"Mount=type=image,source={self.ai_image},destination={MNT_DIR},subpath=/models,readwrite=false"

    def gen_image(self):
        outfile = self.name + ".image"
        print(f"Generating quadlet file: {outfile} ")
        with open(outfile, 'w') as c:
            c.write(
                f"""\
[Image]
Image={self.ai_image}
"""
            )
