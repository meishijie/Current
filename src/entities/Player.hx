package entities;

import base.Being;
import base.Interactable;
import base.Physics;
import com.haxepunk.HXP;
import com.haxepunk.Entity;
import com.haxepunk.graphics.Image;
import com.haxepunk.masks.Circle;
import com.haxepunk.Sfx;
import com.haxepunk.utils.Input;
import com.haxepunk.utils.Key;
import com.haxepunk.utils.Data;
import com.haxepunk.utils.Touch;
import flash.geom.Point;
import haxe.Serializer;
import haxe.Unserializer;
import scenes.Game;

enum Gesture
{
	DOWN;
	DOWNLEFT;
	DOWNRIGHT;
	LEFT;
	RIGHT;
	UP;
	UPLEFT;
	UPRIGHT;
}

typedef PickupType = {
	var number:Int;
	var rooms:Array<String>;
};

class Player extends Physics
{

	public var following:Int; // bubbles following
	public var frozen:Bool;

	public function new(x:Float, y:Float)
	{
		super(x, y);
		var image:Image = new Image("gfx/bubble.png");
		image.centerOrigin();
		graphic = image;
		mask = new Circle(8, -8, -8);

		following = 0;
		bounce = 2;
		_bubbles = new Array<Bubble>();
		_bubbleAngle = 0;
		_shootTime = 0;

		type = "keep";
		frozen = false;

		Input.define("up", [Key.W, Key.UP]);
		Input.define("down", [Key.S, Key.DOWN]);
		Input.define("left", [Key.A, Key.LEFT]);
		Input.define("right", [Key.D, Key.RIGHT]);
		Input.define("grab", [Key.SPACE, Key.SHIFT]);

		if (_enemyTypes == null)
		{
			_enemyTypes = ["fish", "coral"];
			_grabTypes = ["rock", "gem"];
			_tossTypes = ["rock"];
			_bubbleLayers = [6, 12, 18, 24];
		}
	}

	public function loadData()
	{
		// sets max bubbles as well
		maxLayer = Data.readInt("maxLayer", 1);
		// load pickups
		var p = Data.read("pickups");
		if (p != null)
			_pickups = Unserializer.run(p);
		else
			_pickups = new Map<String,PickupType>();
	}

	public function saveData()
	{
		Data.write("maxLayer", maxLayer);
		Data.write("pickups", Serializer.run(_pickups));
	}

	public function hasPickup(pickup:String, ?level:String):Bool
	{
		if (_pickups.exists(pickup))
		{
			if (level == null)
			{
				// just checking type
				return true;
			}
			else
			{
				// checking if we picked up the object in a specific room
				for (room in _pickups.get(pickup).rooms)
				{
					if (room == level)
						return true;
				}
			}
		}
		return false;
	}

	public function getPickup(pickup:String):Int
	{
		if (_pickups.exists(pickup))
			return _pickups.get(pickup).number;
		return 0;
	}

	public function setPickup(pickup:String, room:String)
	{
		var p:PickupType;
		if (_pickups.exists(pickup))
		{
			p = _pickups.get(pickup);
			p.number += 1;
		}
		else
		{
			p = { number: 1, rooms:new Array<String>() };
		}
		p.rooms.push(room);

		// special cases
		switch (pickup)
		{
			case "layer": maxLayer = p.number + 1;
		}

		_pickups.set(pickup, p);
	}

	public function switchRoom(direction:String)
	{
		switch (direction)
		{
			case "left":
				x = Game.levelWidth - 8;
			case "right":
				x = 8;
			case "top":
				y = Game.levelHeight - 8;
			case "bottom":
				y = 8;
		}
		// check if we're in a wall
		if (collideSolid(x, y))
		{
			if (direction == "top" || direction == "bottom")
			{
				findClosestOpeningHoriz();
			}
			else
			{
				findClosestOpeningVert();
			}
		}
		frozen = false;
		velocity.x = velocity.y = 0;
		resetBubbles();
	}

	/**
	 * Sets how many bubble layers we can have
	 */
	public var maxLayer(get_maxLayer, set_maxLayer):Int;
	private function get_maxLayer():Int { return _maxLayer; }
	private function set_maxLayer(value:Int):Int
	{
		// clamp to max layers
		if (value > _bubbleLayers.length)
			value = _bubbleLayers.length;
		_maxLayer = value;
		_maxBubbles = 0;
		for (i in 0 ... value)
		{
			_maxBubbles += _bubbleLayers[i];
		}
		return value;
	}

	public override function kill()
	{
		HXP.scene.remove(this);
		var pop:Sfx = new Sfx("sfx/pop" + #if flash ".mp3" #else ".wav" #end);
		pop.play();
		super.kill();
	}

	public function lastBubble():Bubble
	{
		if (_bubbles.length != 0)
			_bubbles[_bubbles.length - 1];
		return null;
	}

	public override function update()
	{
		if (frozen) return;
		handleMovement();
		handleGrab();
		handleToss();
		handleShoot();

		super.update();

		var e:Entity = collideTypes(_enemyTypes, x, y);
		if (e != null && _bubbles.length == 0)
		{
			if (Std.is(e, Being))
				hurt(cast(e, Being).attack);
			else
				hurt(1);
		}

		var e:Entity = collide("interact", x, y);
		if (e != null)
		{
			var interact:Interactable = cast(e, Interactable);
			if (interact != null)
				interact.activate(this);
		}

		if (collide("exit", x, y) != null)
		{
			cast(scene, Game).finishGame();
			frozen = true;
		}

		// check if player heads off screen
		var game:Game = cast(HXP.scene, Game);
		if (dead)
		{
			game.restart();
		}
		else
		{
			if (x < -width)
				game.switchLevel("left");
			else if (x > Game.levelWidth)
				game.switchLevel("right");
			if (y < -height)
				game.switchLevel("top");
			else if (y > Game.levelHeight)
				game.switchLevel("bottom");

			// rotate bubbles
			_bubbleAngle += 1;
			for (i in 0 ... _bubbles.length)
			{
				moveBubble(i);
			}

			e = collide("bubble", x, y);
			if (e != null)
			{
				var bubble:Bubble = cast(e, Bubble);
				if (bubble != null)
				{
					addBubble(bubble);
				}
			}
		}
	}

	public function resetBubbles()
	{
		for (i in 0 ... _bubbles.length)
		{
			moveBubble(i);
			_bubbles[i].reset = true;
		}
	}

	private function moveBubble(index:Int)
	{
		var layer:Int = -1;
		var numOnLayer:Int = 0;
		var angleIndex:Int = index;

		var total:Int = 0;
		for (i in 0 ... _bubbleLayers.length)
		{
			total += _bubbleLayers[i];
			if (index < total)
			{
				numOnLayer = _bubbleLayers[i];
				layer = i;
				break;
			}
			angleIndex -= _bubbleLayers[i];
		}

		// this bubble is on an undefined layer
		if (layer == -1) return;

		var offsetAngle:Float = (angleIndex % numOnLayer) * 360 / numOnLayer;
		var offsetRadius:Float = layer * 12 + width;
		var angle:Float = (_bubbleAngle + offsetAngle) * HXP.RAD;

		_bubbles[index].targetX = Math.cos(angle) * offsetRadius + x;
		_bubbles[index].targetY = Math.sin(angle) * offsetRadius + y;
	}

	public function removeBubble(?bubble:Bubble)
	{
		if (bubble == null)
		{
			if (_bubbles.length > 0)
				_bubbles.pop().kill();
		}
		else
		{
			_bubbles.remove(bubble);
		}
	}

	private function addBubble(bubble:Bubble)
	{
		if (bubble.owned || _bubbles.length >= _maxBubbles) return;
		_bubbles.push(bubble);
		bubble.owner = this;
		moveBubble(_bubbles.length - 1);
	}

	private function handleMovement()
	{
		if (Input.multiTouchSupported)
		{
			var touchCount:Int = 0;
			for (touch in Input.touches)
			{
				//trace(touch.sceneX + ", " + touch.sceneY);
				acceleration.x = touch.sceneX - x;
				acceleration.y = touch.sceneY - y;
				acceleration.normalize(speed);
				touchCount += 1;
			}
			if (touchCount == 0)
			{
				applyDrag(true, true);
			}
		}
		else
		{
			// Horizontal movement
			if (Input.check("left"))
			{
				acceleration.x = -speed;
			}
			else if (Input.check("right"))
			{
				acceleration.x = speed;
			}
			else
			{
				applyDrag(true, false); // horizontal
			}

			// Vertical movement
			if (Input.check("up"))
			{
				acceleration.y = -speed;
			}
			else if (Input.check("down"))
			{
				acceleration.y = speed;
			}
			else
			{
				applyDrag(false, true); // vertical
			}
		}
	}

	private function handleShoot()
	{
		if (!hasPickup("shoot") || _tossObject != null) return;

		_shootTime -= HXP.elapsed;
		if (Input.mouseDown && _bubbles.length > 0 && _shootTime < 0)
		{
			var bubble:Bubble = _bubbles.pop();
			bubble.shoot(scene.mouseX, scene.mouseY);
			_shootTime = 0.2; // shoot cooldown
		}
	}

	private function handleGrab()
	{
		if (!hasPickup("grab")) return;

		if (Input.check("grab") && _bubbles.length > 0)
		{
			if (_grabObject == null)
			{
				var i:Int = 0;
				while (_grabObject == null && i < _grabTypes.length)
				{
					var e:Entity = HXP.scene.nearestToEntity(_grabTypes[i], this);
					if (e != null && HXP.distance(e.x, e.y, x, y) < 100 && Std.is(e, Physics))
						_grabObject = cast(e, Physics);
					i += 1;
				}
				// check that we got something to grab
				if (_grabObject != null)
				{
					removeBubble();
					_grabTime = 1;
				}
			}
			else if (_grabObject.dead)
			{
				_grabObject = null;
			}
			else
			{
				_grabTime -= HXP.elapsed;
				if (_grabTime < 0)
				{
					removeBubble();
					_grabTime = 1;
				}
				_point.x = x - _grabObject.x;
				_point.y = y - _grabObject.y;
				if (_point.length > 30)
				{
					_point.normalize(8);
					_grabObject.velocity.x += _point.x;
					_grabObject.velocity.y += _point.y;
				}
			}
		}
		else
		{
			_grabObject = null;
		}
	}

	private function handleToss()
	{
		if (!hasPickup("toss")) return;

		if (Input.mousePressed)
		{
			_tossObject = null;
			if (_bubbles.length > 0)
			{
				var i:Int = 0;
				while (_tossObject == null && i < _tossTypes.length)
				{
					var e:Entity = scene.collidePoint(_tossTypes[i], scene.mouseX, scene.mouseY);
					if (e != null && Std.is(e, Physics))
						_tossObject = cast(e, Physics);
					i += 1;
				}
				if (_tossObject != null)
				{
					_tossX = scene.mouseX;
					_tossY = scene.mouseY;
				}
			}
		}
		else if (Input.mouseReleased)
		{
			if (_tossObject != null)
			{
				removeBubble();
				_tossObject.toss(scene.mouseX - _tossX, scene.mouseY - _tossY);
			}
		}
	}

	private static var _enemyTypes:Array<String>;
	private static var _grabTypes:Array<String>;
	private static var _tossTypes:Array<String>;
	private static var _bubbleLayers:Array<Int>;

	private var _grabTime:Float;
	private var _grabObject:Physics;

	// drag objects
	private var _tossX:Float;
	private var _tossY:Float;
	private var _tossTime:Float;
	private var _tossObject:Physics;

	private var _shootTime:Float;

	private var _pickups:Map<String,PickupType>;

	private var _maxBubbles:Int;
	private var _maxLayer:Int;
	private var _bubbles:Array<Bubble>;
	private var _bubbleAngle:Float;

}