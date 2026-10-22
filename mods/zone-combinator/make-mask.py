import numpy as np
from PIL import Image
from PIL import ImageChops
from PIL import ImageOps

# this script will take an image of name img_name.png and create a rough image of the tint needed to add on top of the original image to get the hue-shifted version
# to finish creating the tint after this script runs, the color curves need to be adjusted to make the lighter areas of the image more white and then it needs manual
# painting to clean up whichever portions of the tint don't overlay nicely

# constant-combinator-icon-mask.png and hr-constant-combinator-mask.png were made using the above process
img_name = "constant-combinator"

img = Image.open(img_name + ".png")

alpha = img.getchannel('A')
img = img.convert('RGB')
hsv_img = img.convert('HSV')

hsv = np.array(hsv_img)
hsv[..., 0] = (hsv[..., 0]+100) % 360
new_img_hsv = Image.fromarray(hsv, 'HSV')
new_img = new_img_hsv.convert('RGB')
new_img.putalpha(alpha)

new_img.save(img_name + "-hue.png")

alpha = Image.open(img_name + ".png").getchannel('A')
img = Image.open(img_name + ".png").convert('RGB')
img2 = Image.open(img_name + "-hue.png").convert('RGB')

diff = ImageChops.subtract(img2, img)
gray = ImageOps.grayscale(diff)
gray.save(img_name + "-mask.png")